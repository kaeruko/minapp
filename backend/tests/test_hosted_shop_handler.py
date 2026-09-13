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

import hosted_shop_handler  # noqa: E402


class FakeHostedShopBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def list_shop_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self.last_call = ("list", auth_subject)
        return [
            {
                "app_id": "a" * 32,
                "version": "4",
                "owner_user_id": "b" * 32,
                "owner_display_name": "girls-author",
                "title": "Girls作品",
                "published_at": "2026-09-13T02:00:00Z",
                "sha256": "c" * 64,
            }
        ]

    def create_shop_launch(
        self, auth_subject: str, app_id: str, version: str
    ) -> dict[str, Any]:
        self.last_call = ("launch", auth_subject, app_id, version)
        return {
            "content_path": "/shop/content/token/index.html",
            "expires_in": 600,
        }

    def create_shop_download(
        self, auth_subject: str, app_id: str, version: str
    ) -> dict[str, Any]:
        self.last_call = ("download", auth_subject, app_id, version)
        return {
            "url": "https://download.example.com/app.zip?sig=x",
            "filename": f"{app_id}.zip",
            "sha256": "c" * 64,
            "expires_in": 600,
        }

    def create_shop_report(
        self, auth_subject: str, app_id: str, version: str, reason: str
    ) -> dict[str, Any]:
        self.last_call = ("report", auth_subject, app_id, version, reason)
        return {
            "report_id": "d" * 32,
            "status": "received",
            "created_at": "2026-09-13T03:00:00Z",
        }

    def set_shop_visibility(
        self, auth_subject: str, app_id: str, visibility: str
    ) -> dict[str, Any]:
        self.last_call = ("visibility", auth_subject, app_id, visibility)
        return {"app_id": app_id, "shop_visibility": visibility}

    def get_shop_file(self, token: str, path: str) -> tuple[bytes, str]:
        self.last_call = ("file", token, path)
        return b"<html></html>", "text/html; charset=utf-8"


def _event(
    method: str,
    path: str,
    *,
    subject: str | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request_context: dict[str, Any] = {
        "http": {"method": method},
        "domainName": "girls.example.execute-api.ap-northeast-1.amazonaws.com",
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


class HostedShopHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeHostedShopBackend()
        self.backend_patch = patch.object(
            hosted_shop_handler,
            "_shared_backend",
            return_value=self.backend,
        )
        self.backend_patch.start()

    def tearDown(self) -> None:
        self.backend_patch.stop()

    def test_list_uses_same_shop_shape(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event("GET", "/shop/apps", subject="viewer-sub"), None
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["apps"][0]["version"], "4")
        self.assertEqual(self.backend.last_call, ("list", "viewer-sub"))

    def test_launch_posts_exact_decimal_version(self) -> None:
        app_id = "a" * 32
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{app_id}/launch",
                subject="viewer-sub",
                body={"version": "4"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(
            payload["url"],
            "https://girls.example.execute-api.ap-northeast-1.amazonaws.com/shop/content/token/index.html",
        )
        self.assertEqual(
            self.backend.last_call,
            ("launch", "viewer-sub", app_id, "4"),
        )

    def test_launch_rejects_classic_hex_version_in_hosted_contract(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{'a' * 32}/launch",
                subject="viewer-sub",
                body={"version": "b" * 32},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)

    def test_report_rejects_unknown_fields_without_calling_backend(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{'a' * 32}/reports",
                subject="viewer-sub",
                body={"version": "4", "reason": "その他", "extra": True},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)

    def test_visibility_passes_exact_value(self) -> None:
        app_id = "a" * 32
        response = hosted_shop_handler.lambda_handler(
            _event(
                "PUT",
                f"/apps/{app_id}/shop-visibility",
                subject="author-sub",
                body={"visibility": "listed"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.last_call,
            ("visibility", "author-sub", app_id, "listed"),
        )


if __name__ == "__main__":
    unittest.main()
