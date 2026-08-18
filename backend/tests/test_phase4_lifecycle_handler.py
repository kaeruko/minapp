from __future__ import annotations

import base64
import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import phase4_lifecycle_handler  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def list_my_apps_lifecycle(self, subject: str) -> list[dict[str, Any]]:
        self.last_call = ("list", subject)
        return []

    def upload_app_version(self, subject: str, app_id: str, filename: str, data: bytes) -> dict[str, Any]:
        self.last_call = ("upload", subject, app_id, filename, data)
        return {
            "app_id": app_id,
            "version_id": "b" * 32,
            "group_id": "c" * 32,
            "group_name": "ねんね組",
            "owner_user_id": "d" * 32,
            "owner_login_id": "student-demo",
            "title": "時間割",
            "filename": filename,
            "status": "draft",
            "created_at": "2026-08-17T00:00:00Z",
            "version_number": 2,
            "version_count": 2,
            "is_latest_version": True,
            "is_published": False,
            "app_status": "active",
        }

    def archive_app(self, subject: str, app_id: str) -> None:
        self.last_call = ("archive", subject, app_id)

    def approve_app(self, subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("approve", subject, app_id, version_id)
        return {"app_id": app_id, "version_id": version_id}

    def reject_app(self, subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("reject", subject, app_id, version_id)
        return {"app_id": app_id, "version_id": version_id, "status": "rejected"}

    def unpublish_app(self, subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("unpublish", subject, app_id, version_id)
        return {"app_id": app_id, "version_id": version_id, "status": "unpublished"}


def _event(method: str, path: str, *, subject: str = "sub") -> dict[str, Any]:
    return {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": subject}}},
        },
    }


def _json_post(path: str) -> dict[str, Any]:
    event = _event("POST", path)
    event["headers"] = {"content-type": "application/json"}
    event["body"] = "{}"
    return event


class Phase4LifecycleHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        phase4_lifecycle_handler._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        phase4_lifecycle_handler._BACKEND = None

    def test_list_lifecycle_apps(self) -> None:
        response = phase4_lifecycle_handler.lambda_handler(_event("GET", "/lifecycle/apps"), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"apps": []})
        self.assertEqual(self.backend.last_call, ("list", "sub"))

    def test_binary_version_upload(self) -> None:
        app_id = "a" * 32
        event = _event("POST", f"/apps/{app_id}/versions")
        event["headers"] = {"content-type": "application/zip"}
        event["queryStringParameters"] = {"filename": "update.zip"}
        event["isBase64Encoded"] = True
        event["body"] = base64.b64encode(b"zip").decode("ascii")
        response = phase4_lifecycle_handler.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.backend.last_call, ("upload", "sub", app_id, "update.zip", b"zip"))

    def test_archive_has_no_body(self) -> None:
        app_id = "a" * 32
        response = phase4_lifecycle_handler.lambda_handler(_event("DELETE", f"/apps/{app_id}"), None)
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(self.backend.last_call, ("archive", "sub", app_id))

    def test_approve_uses_lifecycle_backend(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = phase4_lifecycle_handler.lambda_handler(
            _json_post(f"/apps/{app_id}/versions/{version_id}/approve"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("approve", "sub", app_id, version_id))

    def test_reject_uses_moderation_backend(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = phase4_lifecycle_handler.lambda_handler(
            _json_post(f"/apps/{app_id}/versions/{version_id}/reject"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["status"], "rejected")
        self.assertEqual(self.backend.last_call, ("reject", "sub", app_id, version_id))

    def test_unpublish_uses_moderation_backend(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = phase4_lifecycle_handler.lambda_handler(
            _json_post(f"/apps/{app_id}/versions/{version_id}/unpublish"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["status"], "unpublished")
        self.assertEqual(self.backend.last_call, ("unpublish", "sub", app_id, version_id))

    def test_moderation_rejects_non_empty_json_body(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        event = _json_post(f"/apps/{app_id}/versions/{version_id}/reject")
        event["body"] = '{"reason":"no"}'
        response = phase4_lifecycle_handler.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)


if __name__ == "__main__":
    unittest.main()
