from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_entry  # noqa: E402


class FakeBackend:
    pass


def event(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    auth: bool = False,
) -> dict[str, Any]:
    request_context: dict[str, Any] = {"http": {"method": method}}
    if auth:
        request_context["authorizer"] = {
            "jwt": {"claims": {"sub": "sub-owner"}}
        }
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": request_context,
        "headers": {},
    }
    if body is not None:
        result["headers"] = {"content-type": "application/json"}
        result["body"] = json.dumps(body)
    return result


class HostedPreviewEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        hosted_entry._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_entry._BACKEND = None

    def test_owner_preview_session_requires_empty_body_and_authenticated_subject(self) -> None:
        app_id = "3" * 32
        expected = {
            "app_id": app_id,
            "group_id": "2" * 32,
            "source_revision": 4,
            "content_path": "/hosted/preview/" + "A" * 43 + "/index.html",
            "expires_in": 600,
        }
        with patch.object(
            hosted_entry.hosted_app_management,
            "create_preview_session",
            return_value=expected,
        ) as create:
            response = hosted_entry.lambda_handler(
                event(
                    "POST",
                    f"/hosted/my/apps/{app_id}/preview-session",
                    body={},
                    auth=True,
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"]), expected)
        create.assert_called_once_with(self.backend, "sub-owner", app_id)

    def test_owner_preview_session_rejects_unknown_body_fields(self) -> None:
        app_id = "3" * 32
        with patch.object(
            hosted_entry.hosted_app_management,
            "create_preview_session",
        ) as create:
            response = hosted_entry.lambda_handler(
                event(
                    "POST",
                    f"/hosted/my/apps/{app_id}/preview-session",
                    body={"revision": 99},
                    auth=True,
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 400)
        create.assert_not_called()

    def test_preview_content_capability_does_not_require_jwt(self) -> None:
        token = "A" * 43
        with patch.object(
            hosted_entry.hosted_app_management,
            "get_preview_file",
            return_value=(b"<h1>draft</h1>", "text/html; charset=utf-8"),
        ) as get_preview:
            response = hosted_entry.lambda_handler(
                event(
                    "GET",
                    f"/hosted/preview/{token}/index.html",
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        self.assertTrue(response["isBase64Encoded"])
        get_preview.assert_called_once_with(self.backend, token, "index.html")


if __name__ == "__main__":
    unittest.main()
