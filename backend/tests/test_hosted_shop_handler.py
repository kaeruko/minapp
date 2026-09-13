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

import hosted_handler  # noqa: E402
import hosted_shop_handler  # noqa: E402
from hosted_girls_shop_backend import HostedGirlsShopBackend  # noqa: E402
from hosted_user_state_backend import HostedUserStateBackend  # noqa: E402

APP_ID = "a" * 32
USER_ID = "c" * 32


class FakeBackend(HostedGirlsShopBackend):
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def list_shop_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self.calls.append(("list", auth_subject))
        return [
            {
                "app_id": APP_ID,
                "version": "3",
                "title": "放課後ねこ",
                "owner_user_id": USER_ID,
                "owner_display_name": "creator",
                "published_at": "2026-09-13T02:00:00Z",
                "sha256": "d" * 64,
            }
        ]

    def set_shop_visibility(
        self, auth_subject: str, app_id: str, visibility: str
    ) -> dict[str, Any]:
        self.calls.append(("visibility", auth_subject, app_id, visibility))
        return {"app_id": app_id, "shop_visibility": visibility}

    def create_shop_launch(
        self, auth_subject: str, app_id: str, version: str
    ) -> dict[str, Any]:
        self.calls.append(("launch", auth_subject, app_id, version))
        return {
            "content_path": "/shop/content/token-value-abcdefghijklmnopqrstuvwxyz/index.html",
            "runtime_token": "runtime-token-value-abcdefghijklmnopqrstuvwxyz",
            "expires_in": 600,
        }

    def create_shop_download(
        self, auth_subject: str, app_id: str, version: str
    ) -> dict[str, Any]:
        self.calls.append(("download", auth_subject, app_id, version))
        return {
            "url": "https://download.example.com/source.zip?sig=x",
            "filename": f"{app_id}.zip",
            "sha256": "d" * 64,
            "expires_in": 600,
        }

    def create_shop_report(
        self,
        auth_subject: str,
        app_id: str,
        version: str,
        reason: str,
    ) -> dict[str, Any]:
        self.calls.append(("report", auth_subject, app_id, version, reason))
        return {
            "report_id": "e" * 32,
            "status": "received",
            "created_at": "2026-09-13T02:10:00Z",
        }

    def get_shop_file(self, token: str, path: str) -> tuple[bytes, str]:
        self.calls.append(("content", token, path))
        return b"<h1>shop</h1>", "text/html; charset=utf-8"


def _event(
    method: str,
    path: str,
    *,
    subject: str | None = "girls-user-subject",
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    context: dict[str, Any] = {
        "http": {"method": method},
        "domainName": "girls-api.example.com",
    }
    if subject is not None:
        context["authorizer"] = {"jwt": {"claims": {"sub": subject}}}
    event: dict[str, Any] = {
        "rawPath": path,
        "requestContext": context,
    }
    if body is not None:
        event["headers"] = {"content-type": "application/json"}
        event["body"] = json.dumps(body)
    return event


class HostedShopHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        hosted_handler._BACKEND = self.backend
        hosted_shop_handler._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_handler._BACKEND = None
        hosted_shop_handler._BACKEND = None

    def test_list_is_global_shop_route_and_requires_only_authenticated_subject(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event("GET", "/shop/apps"), None
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["apps"][0]["app_id"], APP_ID)
        self.assertEqual(self.backend.calls, [("list", "girls-user-subject")])

    def test_legacy_hosted_backend_is_promoted_before_first_shop_request(self) -> None:
        legacy_backend = object.__new__(HostedUserStateBackend)
        replacement = FakeBackend()
        hosted_handler._BACKEND = legacy_backend
        hosted_shop_handler._BACKEND = None

        with patch.object(
            HostedGirlsShopBackend,
            "from_environment",
            return_value=replacement,
        ) as factory:
            response = hosted_shop_handler.lambda_handler(
                _event("GET", "/shop/apps"), None
            )

        self.assertEqual(response["statusCode"], 200)
        self.assertIs(hosted_handler._BACKEND, replacement)
        self.assertIs(hosted_shop_handler._BACKEND, replacement)
        self.assertEqual(replacement.calls, [("list", "girls-user-subject")])
        factory.assert_called_once_with()

    def test_launch_returns_content_and_isolated_runtime_token(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{APP_ID}/launch",
                body={"version": "3"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(
            payload["url"],
            "https://girls-api.example.com/shop/content/token-value-abcdefghijklmnopqrstuvwxyz/index.html",
        )
        self.assertEqual(
            payload["runtime_token"],
            "runtime-token-value-abcdefghijklmnopqrstuvwxyz",
        )
        self.assertEqual(payload["expires_in"], 600)
        self.assertEqual(
            self.backend.calls,
            [("launch", "girls-user-subject", APP_ID, "3")],
        )

    def test_launch_rejects_non_positive_decimal_version(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{APP_ID}/launch",
                body={"version": "0"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_shop_version")
        self.assertEqual(self.backend.calls, [])

    def test_visibility_has_no_group_id_in_route(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "PUT",
                f"/apps/{APP_ID}/shop-visibility",
                body={"visibility": "listed"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("visibility", "girls-user-subject", APP_ID, "listed")],
        )

    def test_report_requires_exact_fields(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "POST",
                f"/shop/apps/{APP_ID}/reports",
                body={"version": "3", "reason": "その他", "extra": True},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.backend.calls, [])

    def test_shop_content_is_public_and_uses_shop_content_session(self) -> None:
        response = hosted_shop_handler.lambda_handler(
            _event(
                "GET",
                "/shop/content/token-value-abcdefghijklmnopqrstuvwxyz/assets/app.js",
                subject=None,
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("content", "token-value-abcdefghijklmnopqrstuvwxyz", "assets/app.js")],
        )


if __name__ == "__main__":
    unittest.main()
