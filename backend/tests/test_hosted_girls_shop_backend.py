from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_girls_shop_backend import HostedGirlsShopBackend  # noqa: E402
from hosted_shop_managed_backend import HostedShopManagedBackend  # noqa: E402
from hosted_shop_runtime_backend import HostedShopRuntimeBackend  # noqa: E402

APP_ID = "a" * 32
SOURCE_GROUP_ID = "b" * 32
APP_OWNER_ID = "c" * 32
GROUP_OWNER_ID = "d" * 32


def _app() -> dict[str, Any]:
    return {
        "pk": {"S": f"APP#{APP_ID}"},
        "sk": {"S": "META"},
        "entity": {"S": "hosted_app"},
        "app_id": {"S": APP_ID},
        "group_id": {"S": SOURCE_GROUP_ID},
        "owner_user_id": {"S": APP_OWNER_ID},
        "title": {"S": "放課後ねこ"},
        "published_version": {"N": "3"},
        "published_key": {"S": f"hosted/published/{SOURCE_GROUP_ID}/{APP_ID}/versions/000003/source.zip"},
        "published_sha256": {"S": "e" * 64},
        "published_files_json": {"S": json.dumps(["index.html", "app.js"])},
        "published_at": {"S": "2026-09-13T02:00:00Z"},
    }


class RuntimeHarness(HostedShopRuntimeBackend):
    def __init__(self) -> None:
        self.created: list[dict[str, Any]] = []

    def _user_by_auth_subject(self, auth_subject: str) -> Any:
        self.asserted_subject = auth_subject
        return SimpleNamespace(user_id=GROUP_OWNER_ID)

    def _current_shop_app(self, app_id: str) -> dict[str, Any]:
        if app_id != APP_ID:
            raise AssertionError(app_id)
        return _app()

    def _transact_put_new(self, items: list[dict[str, Any]]) -> None:
        self.created = items


class FakeDynamo:
    def __init__(self) -> None:
        self.transactions: list[list[dict[str, Any]]] = []

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        self.transactions.append(TransactItems)


class ManagedHarness(HostedShopManagedBackend):
    def __init__(self) -> None:
        self._table_name = "table"
        self._dynamodb = FakeDynamo()

    def _user_by_auth_subject(self, auth_subject: str) -> Any:
        return SimpleNamespace(user_id=GROUP_OWNER_ID)

    def _app_meta(self, app_id: str) -> dict[str, Any]:
        if app_id != APP_ID:
            raise AssertionError(app_id)
        return _app()

    def _require_active_membership(self, user_id: str, group_id: str) -> dict[str, Any]:
        if user_id != GROUP_OWNER_ID or group_id != SOURCE_GROUP_ID:
            raise AssertionError((user_id, group_id))
        return {
            "role": {"S": "owner"},
            "status": {"S": "active"},
        }


class HostedGirlsShopBackendTests(unittest.TestCase):
    def test_shop_launch_creates_runtime_namespace_outside_source_group(self) -> None:
        backend = RuntimeHarness()
        result = backend.create_shop_launch("viewer-sub", APP_ID, "3")

        self.assertEqual(set(result), {"content_path", "runtime_token", "expires_in"})
        self.assertEqual(len(backend.created), 2)
        content_session, runtime_session = backend.created
        self.assertEqual(content_session["entity"]["S"], "shop_content_session")
        self.assertEqual(runtime_session["entity"]["S"], "shop_runtime_session")
        runtime_group_id = runtime_session["group_id"]["S"]
        self.assertNotEqual(runtime_group_id, SOURCE_GROUP_ID)
        self.assertEqual(runtime_group_id, backend._shop_runtime_group_id(APP_ID))
        self.assertEqual(runtime_session["app_id"]["S"], APP_ID)
        self.assertEqual(runtime_session["user_id"]["S"], GROUP_OWNER_ID)

    def test_source_group_owner_can_list_app_owned_by_member(self) -> None:
        backend = ManagedHarness()
        result = backend.set_shop_visibility("owner-sub", APP_ID, "listed")

        self.assertEqual(
            result,
            {"app_id": APP_ID, "shop_visibility": "listed"},
        )
        self.assertEqual(len(backend._dynamodb.transactions), 1)
        operations = backend._dynamodb.transactions[0]
        self.assertEqual(len(operations), 3)
        listing = operations[2]["Put"]["Item"]
        self.assertEqual(listing["pk"]["S"], "SHOP")
        self.assertEqual(listing["sk"]["S"], f"APP#{APP_ID}")
        # The stored listing remains owned by the actual app author, not the
        # group owner who performed the management action.
        self.assertEqual(listing["owner_user_id"]["S"], APP_OWNER_ID)

    def test_final_backend_mro_uses_runtime_and_managed_shop_overrides(self) -> None:
        self.assertIs(
            HostedGirlsShopBackend.create_shop_launch,
            HostedShopRuntimeBackend.create_shop_launch,
        )
        self.assertIs(
            HostedGirlsShopBackend.set_shop_visibility,
            HostedShopManagedBackend.set_shop_visibility,
        )


if __name__ == "__main__":
    unittest.main()
