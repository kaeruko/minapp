from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from aws_backend import _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_catalog_backend import HostedCatalogBackend  # noqa: E402
from hosted_platform_backend import _number_attr, _runtime_token_hash  # noqa: E402
from hosted_preview_state_backend import HostedPreviewStateBackend  # noqa: E402
from hosted_shop_preview_state_backend import HostedShopPreviewStateBackend  # noqa: E402
from hosted_shop_runtime_backend import HostedShopRuntimeBackend  # noqa: E402


APP_ID = "a" * 32
TOKEN_A = "A" * 43
TOKEN_B = "B" * 43
PREVIEW_TOKEN = "C" * 43


class FakeDynamo:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}

    @staticmethod
    def _s(attr: dict[str, Any]) -> str:
        return attr["S"]

    def get_item(self, **kwargs: Any) -> dict[str, Any]:
        key = kwargs["Key"]
        item = self.items.get((self._s(key["pk"]), self._s(key["sk"])))
        return {} if item is None else {"Item": item}

    def update_item(self, **kwargs: Any) -> dict[str, Any]:
        key = kwargs["Key"]
        item = self.items.get((self._s(key["pk"]), self._s(key["sk"])))
        if item is None:
            raise AssertionError("Tried to increment a missing Runtime session")
        limit = int(kwargs["ExpressionAttributeValues"][":limit"]["N"])
        count = int(item.get("request_count", {"N": "0"})["N"])
        if count >= limit:
            raise AssertionError("Runtime request limit reached in test")
        item["request_count"] = _number_attr(count + 1)
        return {}

    def query(self, **kwargs: Any) -> dict[str, Any]:
        values = kwargs["ExpressionAttributeValues"]
        pk = self._s(values[":pk"])
        prefix = self._s(values[":state_prefix"])
        return {
            "Items": [
                item for (item_pk, item_sk), item in self.items.items()
                if item_pk == pk and item_sk.startswith(prefix)
            ]
        }

    def transact_write_items(self, **kwargs: Any) -> None:
        for operation in kwargs["TransactItems"]:
            if "Put" in operation:
                item = operation["Put"]["Item"]
                self.items[(self._s(item["pk"]), self._s(item["sk"]))] = item
            elif "Delete" in operation:
                key = operation["Delete"]["Key"]
                self.items.pop((self._s(key["pk"]), self._s(key["sk"])), None)
            else:
                raise AssertionError(f"Unknown test DynamoDB operation: {operation}")


class Harness(HostedShopPreviewStateBackend):
    def __init__(self) -> None:
        self._dynamodb = FakeDynamo()
        self._table_name = "metadata"
        self._runtime_dynamodb = FakeDynamo()
        self._runtime_table_name = "runtime"
        self.membership_checks: list[tuple[str, str]] = []
        self._shop_app_active = True

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None:
        return self._dynamodb.items.get((pk, sk))

    def _current_shop_app(self, app_id: str) -> dict[str, Any]:
        if app_id != APP_ID or not self._shop_app_active:
            raise ApiProblem(404, "shop_app_not_found", "Shop app unavailable")
        return {"app_id": _string_attr(app_id)}

    def _require_active_membership(self, user_id: str, group_id: str) -> dict[str, Any]:
        self.membership_checks.append((user_id, group_id))
        raise AssertionError("Shop Runtime must never check source group membership")

    def create_session(self, token: str, user_id: str) -> None:
        self._dynamodb.items[(f"RUNTIMESESSION#{_runtime_token_hash(token)}", "META")] = {
            "entity": _string_attr("shop_runtime_session"),
            "group_id": _string_attr(self._shop_runtime_group_id(APP_ID)),
            "app_id": _string_attr(APP_ID),
            "user_id": _string_attr(user_id),
            "expires_at_epoch": _number_attr(4102444800),
        }


class HostedShopPreviewRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = Harness()
        self.backend.create_session(TOKEN_A, "user-a")
        self.backend.create_session(TOKEN_B, "user-b")

    def test_method_resolution_preserves_both_runtime_behaviors(self) -> None:
        self.assertIs(
            HostedShopPreviewStateBackend._consume_runtime_request,
            HostedShopRuntimeBackend._consume_runtime_request,
        )
        self.assertIs(
            HostedShopPreviewStateBackend.get_runtime_user_state,
            HostedPreviewStateBackend.get_runtime_user_state,
        )
        self.assertIs(
            HostedShopPreviewStateBackend.get_runtime_state,
            HostedCatalogBackend.get_runtime_state,
        )

    def test_public_shop_personal_state_works_without_membership(self) -> None:
        with self.assertRaises(ApiProblem) as missing:
            self.backend.get_runtime_user_state(TOKEN_A, "memo")
        self.assertEqual(missing.exception.error, "state_not_found")

        self.assertEqual(
            self.backend.set_runtime_user_state(TOKEN_A, "memo", {"shop": "町中華"})["value"],
            {"shop": "町中華"},
        )
        self.assertEqual(
            self.backend.get_runtime_user_state(TOKEN_A, "memo")["value"],
            {"shop": "町中華"},
        )
        self.assertEqual(self.backend.membership_checks, [])

    def test_public_shop_users_have_isolated_personal_state(self) -> None:
        self.backend.set_runtime_user_state(TOKEN_A, "memo", 1)
        with self.assertRaises(ApiProblem) as missing:
            self.backend.get_runtime_user_state(TOKEN_B, "memo")
        self.assertEqual(missing.exception.error, "state_not_found")
        self.backend.set_runtime_user_state(TOKEN_B, "memo", 2)
        self.assertEqual(self.backend.get_runtime_user_state(TOKEN_A, "memo")["value"], 1)
        self.assertEqual(self.backend.get_runtime_user_state(TOKEN_B, "memo")["value"], 2)
        self.assertEqual(self.backend.membership_checks, [])

    def test_public_shop_shared_state_works_without_membership(self) -> None:
        self.backend.set_runtime_state(TOKEN_A, "config", {"value": 1})
        self.assertEqual(
            self.backend.get_runtime_state(TOKEN_B, "config")["value"], {"value": 1},
        )
        self.assertEqual(self.backend.membership_checks, [])

    def test_invalid_shop_namespace_fails_closed(self) -> None:
        session = self.backend._get_item(
            pk=f"RUNTIMESESSION#{_runtime_token_hash(TOKEN_A)}", sk="META",
        )
        assert session is not None
        session["group_id"] = _string_attr("b" * 32)
        with self.assertRaisesRegex(RuntimeError, "namespace does not match"):
            self.backend.get_runtime_user_state(TOKEN_A, "memo")
        self.assertEqual(self.backend.membership_checks, [])

    def test_unlisted_shop_app_cannot_use_runtime(self) -> None:
        self.backend._shop_app_active = False
        with self.assertRaises(ApiProblem) as error:
            self.backend.get_runtime_user_state(TOKEN_A, "memo")
        self.assertEqual(error.exception.error, "shop_app_not_found")


if __name__ == "__main__":
    unittest.main()
