from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import shop_handler  # noqa: E402


class FakeShopBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def list_shop_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self.last_call = ("list", auth_subject)
        return [
            {
                "app_id": "a" * 32,
                "version_id": "b" * 32,
                "owner_user_id": "c" * 32,
                "owner_display_name": "作者",
                "title": "ショップ作品",
                "status": "approved",
                "filename": "app.zip",
                "created_at": "2026-09-13T00:00:00Z",
                "reviewed_at": "2026-09-13T01:00:00Z",
                "sha256": "d" * 64,
            }
        ]

    def create_shop_launch(
        self, auth_subject: str, app_id: str, version_id: str
    ) -> dict[str, Any]:
        self.last_call = ("launch", auth_subject, app_id, version_id)
        return {
            "content_path": "/launch/shop-token/index.html",
            "expires_in": 600,
        }

    def create_shop_download(
        self, auth_subject: str, app_id: str, version_id: str
    ) -> dict[str, Any]:
        self.last_call = ("download", auth_subject, app_id, version_id)
        return {
            "url": "https://download.example.com/app.zip?sig=x",
            "filename": "app.zip",
            "sha256": "d" * 64,
            "expires_in": 600,
        }

    def create_shop_report(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
        reason: str,
    ) -> dict[str, Any]:
        self.last_call = ("report", auth_subject, app_id, version_id, reason)
        return {
            "report_id": "e" * 32,
            "status": "received",
            "created_at": "2026-09-13T02:00:00Z",
        }

    def set_shop_visibility(
        self, auth_subject: str, app_id: str, visibility: str
    ) -> dict[str, Any]:
        self.last_call = ("visibility", auth_subject, app_id, visibility)
        return {"app_id": app_id, "shop_visibility": visibility}


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


class ShopHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeShopBackend()
        shop_handler._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        shop_handler._BACKEND = None

    def test_list_requires_authentication(self) -> None:
        response = shop_handler.lambda_handler(_event("GET", "/shop/apps"), None)
        self.assertEqual(response["statusCode"], 401)

    def test_list_uses_authenticated_subject(self) -> None:
        response = shop_handler.lambda_handler(
            _event("GET", "/shop/apps", subject="viewer-sub"), None
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["apps"][0]["title"], "ショップ作品")
        self.assertEqual(self.backend.last_call, ("list", "viewer-sub"))

    def test_common_launch_contract_passes_exact_version(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{app_id}/launch",
                subject="viewer-sub",
                body={"version": version_id},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(
            payload["url"],
            "https://example.execute-api.ap-northeast-1.amazonaws.com/launch/shop-token/index.html",
        )
        self.assertEqual(
            self.backend.last_call,
            ("launch", "viewer-sub", app_id, version_id),
        )

    def test_common_download_contract_passes_exact_version(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{app_id}/download",
                subject="viewer-sub",
                body={"version": version_id},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.last_call,
            ("download", "viewer-sub", app_id, version_id),
        )

    def test_common_report_contract_passes_exact_version_and_reason(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{app_id}/reports",
                subject="viewer-sub",
                body={"version": version_id, "reason": "その他"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.last_call,
            ("report", "viewer-sub", app_id, version_id, "その他"),
        )

    def test_common_action_rejects_wrong_version_format_without_fallback(self) -> None:
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{'a' * 32}/launch",
                subject="viewer-sub",
                body={"version": "1"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)

    def test_common_action_rejects_unknown_body_fields(self) -> None:
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{'a' * 32}/download",
                subject="viewer-sub",
                body={"version": "b" * 32, "unexpected": True},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)

    def test_visibility_is_authorized_through_backend_with_exact_value(self) -> None:
        app_id = "a" * 32
        response = shop_handler.lambda_handler(
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

    def test_legacy_versioned_launch_remains_supported(self) -> None:
        app_id = "a" * 32
        version_id = "b" * 32
        response = shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{app_id}/versions/{version_id}/launch",
                subject="viewer-sub",
                body={},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.last_call,
            ("launch", "viewer-sub", app_id, version_id),
        )


if __name__ == "__main__":
    unittest.main()
