from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_legal_backend import HostedLegalBackend  # noqa: E402


class LaunchBackendHarness(HostedLegalBackend):
    def __init__(
        self,
        *,
        active_member: bool = True,
        app_in_group: bool = True,
        published: bool = True,
        fail_transaction: bool = False,
    ) -> None:
        self.active_member = active_member
        self.app_in_group = app_in_group
        self.published = published
        self.fail_transaction = fail_transaction
        self.attempted_batches: list[list[dict[str, Any]]] = []
        self.committed_batches: list[list[dict[str, Any]]] = []

    def _user_by_auth_subject(self, auth_subject: str) -> Any:
        self.last_auth_subject = auth_subject
        return SimpleNamespace(user_id="1" * 32)

    def _require_active_membership(self, user_id: str, group_id: str) -> dict[str, Any]:
        if not self.active_member:
            raise ApiProblem(403, "forbidden", "not a member")
        return {"role": {"S": "member"}}

    def _require_app_in_group(self, app_id: str, group_id: str) -> dict[str, Any]:
        if not self.app_in_group:
            raise ApiProblem(404, "app_not_found", "app is outside this group")
        app: dict[str, Any] = {
            "app_id": {"S": app_id},
            "group_id": {"S": group_id},
        }
        if self.published:
            app.update(
                {
                    "published_version": {"N": "3"},
                    "published_key": {"S": f"hosted/published/{group_id}/{app_id}/3/source.zip"},
                    "published_sha256": {"S": "a" * 64},
                    "published_files_json": {"S": '["index.html","assets/app.js"]'},
                }
            )
        return app

    def _require_not_deleting(self, app: dict[str, Any]) -> None:
        del app

    def _transact_put_new(self, items: list[dict[str, Any]]) -> None:
        self.attempted_batches.append(items)
        if self.fail_transaction:
            raise RuntimeError("forced launch transaction failure")
        self.committed_batches.append(items)


class HostedLaunchBackendTests(unittest.TestCase):
    group_id = "2" * 32
    app_id = "3" * 32

    def test_launch_creates_content_and_runtime_capabilities_atomically(self) -> None:
        backend = LaunchBackendHarness()

        result = backend.create_launch_session("sub-member", self.group_id, self.app_id)

        self.assertEqual(result["content_expires_in"], 600)
        self.assertEqual(result["runtime_expires_in"], 600)
        self.assertEqual(result["published_version"], 3)
        self.assertRegex(
            result["content_path"],
            r"^/hosted/content/[A-Za-z0-9_-]{32,128}/index\.html$",
        )
        self.assertRegex(result["runtime_token"], r"^[A-Za-z0-9_-]{32,64}$")
        self.assertEqual(len(backend.committed_batches), 1)
        self.assertEqual(len(backend.committed_batches[0]), 2)

        items_by_entity = {
            item["entity"]["S"]: item for item in backend.committed_batches[0]
        }
        self.assertEqual(set(items_by_entity), {"hosted_content_session", "runtime_session"})
        for item in items_by_entity.values():
            self.assertEqual(item["user_id"]["S"], "1" * 32)
            self.assertEqual(item["group_id"]["S"], self.group_id)
            self.assertEqual(item["app_id"]["S"], self.app_id)

        content_token = result["content_path"].split("/")[3]
        runtime_token = result["runtime_token"]
        serialized_items = repr(backend.committed_batches[0])
        self.assertNotIn(content_token, serialized_items)
        self.assertNotIn(runtime_token, serialized_items)

    def test_non_member_cannot_create_launch(self) -> None:
        backend = LaunchBackendHarness(active_member=False)
        with self.assertRaises(ApiProblem) as raised:
            backend.create_launch_session("sub-outsider", self.group_id, self.app_id)
        self.assertEqual(raised.exception.status_code, 403)
        self.assertEqual(backend.attempted_batches, [])

    def test_cross_group_app_is_rejected(self) -> None:
        backend = LaunchBackendHarness(app_in_group=False)
        with self.assertRaises(ApiProblem) as raised:
            backend.create_launch_session("sub-member", self.group_id, self.app_id)
        self.assertEqual(raised.exception.error, "app_not_found")
        self.assertEqual(backend.attempted_batches, [])

    def test_unpublished_app_is_rejected(self) -> None:
        backend = LaunchBackendHarness(published=False)
        with self.assertRaises(ApiProblem) as raised:
            backend.create_launch_session("sub-member", self.group_id, self.app_id)
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.error, "app_unpublished")
        self.assertEqual(backend.attempted_batches, [])

    def test_transaction_failure_preserves_original_failure_without_partial_commit(self) -> None:
        backend = LaunchBackendHarness(fail_transaction=True)
        with self.assertRaisesRegex(RuntimeError, "forced launch transaction failure"):
            backend.create_launch_session("sub-member", self.group_id, self.app_id)
        self.assertEqual(len(backend.attempted_batches), 1)
        self.assertEqual(len(backend.attempted_batches[0]), 2)
        self.assertEqual(backend.committed_batches, [])


if __name__ == "__main__":
    unittest.main()
