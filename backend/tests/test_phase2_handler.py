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

import handler  # noqa: E402


class FakePhase2Backend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def upload_app(
        self,
        auth_subject: str,
        group_id: str,
        title: str,
        filename: str,
        zip_bytes: bytes,
        description: str | None = None,
    ) -> dict[str, Any]:
        self.last_call = ("upload", auth_subject, group_id, title, filename, zip_bytes, description)
        payload: dict[str, Any] = {
            "app_id": "b" * 32,
            "version_id": "c" * 32,
            "group_id": group_id,
            "group_name": "ねんね組",
            "owner_user_id": "d" * 32,
            "owner_login_id": "student-test",
            "title": title,
            "filename": filename,
            "status": "draft",
            "created_at": "2026-08-18T00:00:00Z",
        }
        if description is not None:
            payload["description"] = description
        return payload

    def list_my_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self.last_call = ("list_my_apps", auth_subject)
        return []

    def submit_app(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("submit", auth_subject, app_id, version_id)
        return {"app_id": app_id, "version_id": version_id, "status": "pending_review"}

    def list_review_queue(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        self.last_call = ("review_queue", auth_subject, group_id)
        return []

    def create_preview(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("preview", auth_subject, app_id, version_id)
        return {"content_path": "/content/abcdefghijklmnopqrstuvwxyzABCDEFG123456/index.html", "expires_in": 900}

    def approve_app(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("approve", auth_subject, app_id, version_id)
        return {"app_id": app_id, "version_id": version_id, "status": "approved"}

    def get_preview_file(self, token: str, path: str) -> tuple[bytes, str]:
        self.last_call = ("content", token, path)
        return b"<!doctype html><h1>preview</h1>", "text/html; charset=utf-8"


def _auth_context(subject: str = "cognito-sub") -> dict[str, Any]:
    return {
        "http": {"method": "GET"},
        "domainName": "example.execute-api.ap-northeast-1.amazonaws.com",
        "authorizer": {"jwt": {"claims": {"sub": subject}}},
    }


def _json_event(method: str, path: str, *, subject: str = "cognito-sub") -> dict[str, Any]:
    context = _auth_context(subject)
    context["http"] = {"method": method}
    return {
        "rawPath": path,
        "requestContext": context,
        "headers": {"content-type": "application/json"},
        "body": "{}",
    }


class Phase2HandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakePhase2Backend()
        handler._BACKEND = self.backend

    def tearDown(self) -> None:
        handler._BACKEND = None

    def test_binary_zip_upload_calls_backend(self) -> None:
        group_id = "a" * 32
        zip_bytes = b"PK-test"
        context = _auth_context()
        context["http"] = {"method": "POST"}
        response = handler.lambda_handler(
            {
                "rawPath": f"/groups/{group_id}/apps",
                "requestContext": context,
                "queryStringParameters": {"title": "時間割", "filename": "timetable.zip"},
                "headers": {"content-type": "application/zip"},
                "body": base64.b64encode(zip_bytes).decode("ascii"),
                "isBase64Encoded": True,
            },
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.last_call,
            ("upload", "cognito-sub", group_id, "時間割", "timetable.zip", zip_bytes, None),
        )

    def test_binary_zip_upload_accepts_optional_description(self) -> None:
        group_id = "a" * 32
        zip_bytes = b"PK-test"
        description = "今日の時間割を確認する\nアプリです。"
        context = _auth_context()
        context["http"] = {"method": "POST"}
        response = handler.lambda_handler(
            {
                "rawPath": f"/groups/{group_id}/apps",
                "requestContext": context,
                "queryStringParameters": {
                    "title": "時間割",
                    "filename": "timetable.zip",
                    "description": description,
                },
                "headers": {"content-type": "application/zip"},
                "body": base64.b64encode(zip_bytes).decode("ascii"),
                "isBase64Encoded": True,
            },
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.last_call,
            ("upload", "cognito-sub", group_id, "時間割", "timetable.zip", zip_bytes, description),
        )
        self.assertEqual(json.loads(response["body"])["description"], description)

    def test_upload_rejects_empty_description_when_parameter_is_present(self) -> None:
        group_id = "a" * 32
        context = _auth_context()
        context["http"] = {"method": "POST"}
        response = handler.lambda_handler(
            {
                "rawPath": f"/groups/{group_id}/apps",
                "requestContext": context,
                "queryStringParameters": {
                    "title": "時間割",
                    "filename": "timetable.zip",
                    "description": "",
                },
                "headers": {"content-type": "application/zip"},
                "body": base64.b64encode(b"PK-test").decode("ascii"),
                "isBase64Encoded": True,
            },
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")

    def test_upload_rejects_non_base64_binary_transport(self) -> None:
        group_id = "a" * 32
        context = _auth_context()
        context["http"] = {"method": "POST"}
        response = handler.lambda_handler(
            {
                "rawPath": f"/groups/{group_id}/apps",
                "requestContext": context,
                "queryStringParameters": {"title": "時間割", "filename": "timetable.zip"},
                "headers": {"content-type": "application/zip"},
                "body": "raw",
            },
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_zip_transport")

    def test_preview_returns_absolute_api_gateway_url(self) -> None:
        app_id = "b" * 32
        version_id = "c" * 32
        response = handler.lambda_handler(
            _json_event("POST", f"/apps/{app_id}/versions/{version_id}/preview"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertTrue(payload["url"].startswith("https://example.execute-api.ap-northeast-1.amazonaws.com/content/"))
        self.assertEqual(self.backend.last_call, ("preview", "cognito-sub", app_id, version_id))

    def test_preview_content_is_base64_and_locked_down(self) -> None:
        token = "abcdefghijklmnopqrstuvwxyzABCDEFG123456"
        response = handler.lambda_handler(
            {
                "rawPath": f"/content/{token}/index.html",
                "requestContext": {"http": {"method": "GET"}},
            },
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertTrue(response["isBase64Encoded"])
        self.assertIn("connect-src 'none'", response["headers"]["content-security-policy"])
        self.assertEqual(base64.b64decode(response["body"]), b"<!doctype html><h1>preview</h1>")


if __name__ == "__main__":
    unittest.main()
