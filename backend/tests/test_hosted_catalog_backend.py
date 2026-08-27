from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_catalog_backend import HostedCatalogBackend  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito, FakeDynamoDb  # noqa: E402


class QuotaFakeDynamoDb(FakeDynamoDb):
    def update_item(
        self,
        *,
        TableName: str,
        Key: dict[str, dict[str, str]],
        UpdateExpression: str,
        ConditionExpression: str,
        ExpressionAttributeValues: dict[str, dict[str, str]],
    ) -> dict[str, Any]:
        del TableName
        if "request_count" not in UpdateExpression or "request_count" not in ConditionExpression:
            raise AssertionError((UpdateExpression, ConditionExpression))
        key = (self._s(Key["pk"]), self._s(Key["sk"]))
        item = self.items.get(key)
        if item is None:
            raise FakeAwsError("ConditionalCheckFailedException")
        current = int(item.get("request_count", {"N": "0"})["N"])
        limit = int(ExpressionAttributeValues[":limit"]["N"])
        if current >= limit:
            raise FakeAwsError("ConditionalCheckFailedException")
        replacement = dict(item)
        replacement["request_count"] = {"N": str(current + 1)}
        self.items[key] = replacement
        return {}


class HostedCatalogBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = QuotaFakeDynamoDb()
        self.runtime = QuotaFakeDynamoDb()
        self.backend = HostedCatalogBackend(
            cognito=self.cognito,
            dynamodb=self.metadata,
            runtime_dynamodb=self.runtime,
            user_pool_id="pool",
            app_client_id="client",
            table_name="metadata",
            runtime_table_name="runtime",
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"]

    def test_builtin_catalog_matches_mobile_builtin_ids(self) -> None:
        builtins = self.backend.list_builtin_templates()
        self.assertEqual(
            {item["builtin_id"] for item in builtins},
            {"shiba-game", "shiba-goshujin"},
        )
        self.assertTrue(all(item["version"] == 1 for item in builtins))

    def test_owner_can_install_fork_list_and_delete_builtin(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "月影荘")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-goshujin")
        self.assertEqual(installed["source_kind"], "builtin")
        self.assertFalse(installed["editable"])

        forked = self.backend.fork_app(
            alice,
            group["group_id"],
            installed["app_id"],
            "うちのごしゅじんどこわん",
        )
        self.assertEqual(forked["source_kind"], "fork")
        self.assertTrue(forked["editable"])
        self.assertEqual(forked["parent_app_id"], installed["app_id"])
        self.assertEqual(forked["builtin_id"], "shiba-goshujin")

        apps = self.backend.list_group_apps(alice, group["group_id"])
        self.assertEqual({app["app_id"] for app in apps}, {installed["app_id"], forked["app_id"]})

        self.backend.delete_hosted_app(alice, group["group_id"], forked["app_id"])
        remaining = self.backend.list_group_apps(alice, group["group_id"])
        self.assertEqual([app["app_id"] for app in remaining], [installed["app_id"]])

    def test_duplicate_builtin_install_is_rejected(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "秘密基地")
        self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        with self.assertRaises(ApiProblem) as caught:
            self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "builtin_already_installed")

    def test_member_can_list_but_cannot_install(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "創作部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])
        self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        self.assertEqual(len(self.backend.list_group_apps(bob, group["group_id"])), 1)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.install_builtin(bob, group["group_id"], "shiba-goshujin")
        self.assertEqual(caught.exception.status_code, 403)

    def test_app_count_guard_applies_to_forks(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "設定資料室")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        with patch("hosted_catalog_backend.MAX_APPS_PER_GROUP", 1):
            with self.assertRaises(ApiProblem) as caught:
                self.backend.fork_app(alice, group["group_id"], installed["app_id"], "fork")
        self.assertEqual(caught.exception.error, "app_limit_reached")

    def test_runtime_key_and_storage_quotas_are_enforced(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "小説部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])

        with patch("hosted_catalog_backend.MAX_RUNTIME_KEYS_PER_APP", 1):
            self.backend.set_runtime_state(session["token"], "chapter.one", {"x": 1})
            with self.assertRaises(ApiProblem) as caught:
                self.backend.set_runtime_state(session["token"], "chapter.two", {"x": 2})
        self.assertEqual(caught.exception.error, "runtime_key_limit_reached")

        with patch("hosted_catalog_backend.MAX_RUNTIME_BYTES_PER_APP", 10):
            with self.assertRaises(ApiProblem) as caught:
                self.backend.set_runtime_state(session["token"], "chapter.one", "0123456789")
        self.assertEqual(caught.exception.error, "runtime_storage_limit_reached")

    def test_runtime_session_request_budget_is_atomic_and_fail_closed(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "なりきり部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])

        with patch("hosted_catalog_backend.MAX_RUNTIME_REQUESTS_PER_SESSION", 2):
            for _ in range(2):
                with self.assertRaises(ApiProblem) as missing:
                    self.backend.get_runtime_state(session["token"], "missing")
                self.assertEqual(missing.exception.error, "state_not_found")
            with self.assertRaises(ApiProblem) as limited:
                self.backend.get_runtime_state(session["token"], "missing")
        self.assertEqual(limited.exception.status_code, 429)
        self.assertEqual(limited.exception.error, "runtime_request_limit_reached")

    def test_delete_app_removes_runtime_state(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "交換日記")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])
        self.backend.set_runtime_state(session["token"], "diary.today", {"text": "わん"})
        self.assertTrue(self.runtime.items)
        self.backend.delete_hosted_app(alice, group["group_id"], installed["app_id"])
        self.assertFalse(self.runtime.items)


if __name__ == "__main__":
    unittest.main()
