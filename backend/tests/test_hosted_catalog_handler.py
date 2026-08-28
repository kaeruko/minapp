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

    def get_editable_source(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> tuple[bytes, dict[str, Any]]:
        self.calls.append(("get_editable_source", auth_subject, group_id, app_id))
        return b"zip", {"revision": 2, "sha256": "a" * 64, "files": ["index.html"]}

    def update_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
        zip_bytes: bytes,
    ) -> dict[str, Any]:
        self.calls.append(
            ("update_editable_source", auth_subject, group_id, app_id, expected_revision, zip_bytes)
        )
        return {"revision": expected_revision + 1}

    def publish_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
    ) -> dict[str, Any]:
        self.calls.append(("publish_app", auth_subject, group_id, app_id, expected_revision))
        return {"published_version": 1, "source_revision": expected_revision}

    def create_published_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]:
        self.calls.append(("create_published_session", auth_subject, group_id, app_id))
        return {"content_path": "/hosted/content/token-value/index.html", "expires_in": 600}

    def get_published_file(self, token: str, path: str) -> tuple[bytes, str]:
        self.calls.append(("get_published_file", token, path))
        return b"<h1>published</h1>", "text/html; charset=utf-8"


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

    def test_source_get_returns_binary_revision_headers(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_handler.lambda_handler(
            event("GET", f"/hosted/groups/{group_id}/apps/{app_id}/source", auth=True), None
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertTrue(response["isBase64Encoded"])
        self.assertEqual(response["headers"]["x-minapp-source-revision"], "2")
        self.assertEqual(base64.b64decode(response["body"]), b"zip")

    def test_source_update_requires_binary_zip_and_revision(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        request = event("POST", f"/hosted/groups/{group_id}/apps/{app_id}/source", auth=True)
        request.update(
            {
                "headers": {"content-type": "application/zip"},
                "body": base64.b64encode(b"zip-v3").decode("ascii"),
                "isBase64Encoded": True,
                "queryStringParameters": {"revision": "2"},
            }
        )
        response = hosted_handler.lambda_handler(request, None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("update_editable_source", "sub-alice", group_id, app_id, 2, b"zip-v3")],
        )

    def test_publish_and_session_routes_are_authenticated(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        publish = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/publish",
                body={"revision": 2},
                auth=True,
            ),
            None,
        )
        session = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/published-session",
                body={},
                auth=True,
            ),
            None,
        )
        self.assertEqual((publish["statusCode"], session["statusCode"]), (201, 201))

    def test_published_content_is_binary_and_does_not_require_jwt(self) -> None:
        response = hosted_handler.lambda_handler(
            event("GET", "/hosted/content/abcdefghijklmnopqrstuvwxyzABCDEFGH/index.html"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertIn("frame-ancestors", response["headers"]["content-security-policy"])
        self.assertEqual(base64.b64decode(response["body"]), b"<h1>published</h1>")


if __name__ == "__main__":
    unittest.main()
