from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_handler  # noqa: E402
from test_hosted_handler import FakeBackend, event  # noqa: E402


class CatalogFakeBackend(FakeBackend):
    def list_builtin_templates(self) -> list[dict[str, Any]]:
        self.calls.append(("list_builtin_templates",))
        return [{"builtin_id": "shiba-game", "version": 1, "title": "しば犬どんぐりキャッチ"}]

    def list_group_apps(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        self.calls.append(("list_group_apps", auth_subject, group_id))
        return []

    def install_builtin(
        self, auth_subject: str, group_id: str, builtin_id: str
    ) -> dict[str, Any]:
        self.calls.append(("install_builtin", auth_subject, group_id, builtin_id))
        return {
            "app_id": "3" * 32,
            "group_id": group_id,
            "title": "しば犬どんぐりキャッチ",
            "source_kind": "builtin",
        }

    def fork_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        title: str,
    ) -> dict[str, Any]:
        self.calls.append(("fork_app", auth_subject, group_id, app_id, title))
        return {
            "app_id": "4" * 32,
            "group_id": group_id,
            "title": title,
            "source_kind": "fork",
            "parent_app_id": app_id,
        }

    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        self.calls.append(("delete_hosted_app", auth_subject, group_id, app_id))


class HostedCatalogHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = CatalogFakeBackend()
        hosted_handler._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_handler._BACKEND = None

    def test_builtin_catalog_is_public(self) -> None:
        response = hosted_handler.lambda_handler(event("GET", "/hosted/builtins"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["builtins"][0]["builtin_id"], "shiba-game")
        self.assertEqual(self.backend.calls, [("list_builtin_templates",)])

    def test_install_builtin_uses_authenticated_owner(self) -> None:
        group_id = "2" * 32
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/install",
                body={"builtin_id": "shiba-game"},
                auth=True,
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls,
            [("install_builtin", "sub-alice", group_id, "shiba-game")],
        )

    def test_fork_requires_exact_title_field(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/fork",
                body={"title": "月影荘版"},
                auth=True,
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls,
            [("fork_app", "sub-alice", group_id, app_id, "月影荘版")],
        )

    def test_delete_app_returns_no_content(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_handler.lambda_handler(
            event("DELETE", f"/hosted/groups/{group_id}/apps/{app_id}", auth=True),
            None,
        )
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(
            self.backend.calls,
            [("delete_hosted_app", "sub-alice", group_id, app_id)],
        )


if __name__ == "__main__":
    unittest.main()
