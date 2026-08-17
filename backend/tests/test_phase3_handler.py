from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import phase3_handler  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def list_mobile_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self.last_call = ("list_mobile_apps", auth_subject)
        return [
            {
                "app_id": "a" * 32,
                "version_id": "b" * 32,
                "group_id": "c" * 32,
                "group_name": "ねんね組",
                "owner_user_id": "d" * 32,
                "owner_login_id": "student-demo",
                "title": "時間割",
                "filename": "app.zip",
                "status": "approved",
                "created_at": "2026-08-17T00:00:00Z",
                "reviewed_at": "2026-08-17T01:00:00Z",
            }
        ]

    def create_launch(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self.last_call = ("create_launch", auth_subject, app_id, version_id)
        return {"content_path": "/launch/token123/index.html", "expires_in": 600}

    def get_launch_file(self, token: str, path: str) -> tuple[bytes, str]:
        self.last_call = ("get_launch_file", token, path)
        return b"<h1>ok</h1>", "text/html; charset=utf-8"


def _event(
    method: str,
    path: str,
    *,
    subject: str | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request_context: dict[str, Any] = {
        "http": {"method": method},
        "domainName": "example.execute-api.ap-northeast-1.amazonaws.com",
    }
    if subject is not None:
        request_context["authorizer"] = {"jwt": {"claims": {"sub": subject}}}
    event: dict[str, Any] = {
        "rawPath": path,
        "requestContext": request_context,
    }
    if body is not None:
        event["headers"] = {"content-type": "application/json"}
        event["body"] = json.dumps(body)
    return event


class Phase3HandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        phase3_handler._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        phase3_handler._BACKEND = None

    def test_mobile_catalog_requires_authentication(self) -> None:
        response = phase3_handler.lambda_handler(_event("GET", "/mobile/apps"), None)
        self.assertEqual(response["statusCode"], 401)

    def test_mobile_catalog_uses_authenticated_subject(self) -> None:
        response = phase3_handler.lambda_handler(
            _event("GET", "/mobile/apps", subject="student-sub"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["apps"][0]["title"], "時間割")
        self.assertEqual(self.backend.last_call, ("list_mobile_apps", "student-sub"))

    def test_launch_returns_absolute_short_lived_url(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = phase3_handler.lambda_handler(
            _event(
                "POST",
                f"/mobile/apps/{app_id}/versions/{version_id}/launch",
                subject="student-sub",
                body={},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(
            payload["url"],
            "https://example.execute-api.ap-northeast-1.amazonaws.com/launch/token123/index.html",
        )
        self.assertEqual(payload["expires_in"], 600)
        self.assertEqual(
            self.backend.last_call,
            ("create_launch", "student-sub", app_id, version_id),
        )

    def test_launch_rejects_nonempty_json_body(self) -> None:
        response = phase3_handler.lambda_handler(
            _event(
                "POST",
                f"/mobile/apps/{'a' * 32}/versions/{'b' * 32}/launch",
                subject="student-sub",
                body={"unexpected": True},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)

    def test_launch_content_does_not_require_jwt(self) -> None:
        response = phase3_handler.lambda_handler(
            _event("GET", "/launch/token123/index.html"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertTrue(response["isBase64Encoded"])
        self.assertIn("connect-src 'none'", response["headers"]["content-security-policy"])
        self.assertEqual(self.backend.last_call, ("get_launch_file", "token123", "index.html"))


if __name__ == "__main__":
    unittest.main()
