from __future__ import annotations

import json
import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from errors import ApiProblem  # noqa: E402
from hosted_user_state_backend import HostedUserStateBackend  # noqa: E402


class FakeRuntimeDynamo:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}

    @staticmethod
    def _s(attribute: dict[str, Any]) -> str:
        value = attribute.get("S")
        if not isinstance(value, str):
            raise AssertionError("expected DynamoDB string attribute")
        return value

    def get_item(self, **kwargs: Any) -> dict[str, Any]:
        key = kwargs["Key"]
        item = self.items.get((self._s(key["pk"]), self._s(key["sk"])))
        return {} if item is None else {"Item": item}

    def query(self, **kwargs: Any) -> dict[str, Any]:
        values = kwargs["ExpressionAttributeValues"]
        pk = self._s(values[":pk"])
        prefix = self._s(values[":state_prefix"])
        return {
            "Items": [
                item
                for (item_pk, item_sk), item in self.items.items()
                if item_pk == pk and item_sk.startswith(prefix)
            ]
        }

    def transact_write_items(self, **kwargs: Any) -> None:
        for operation in kwargs["TransactItems"]:
            if "Put" in operation:
                item = operation["Put"]["Item"]
                self.items[(self._s(item["pk"]), self._s(item["sk"]))] = item
                continue
            if "Delete" in operation:
                key = operation["Delete"]["Key"]
                self.items.pop((self._s(key["pk"]), self._s(key["sk"])), None)
                continue
            raise AssertionError(f"unsupported transaction operation: {operation}")


class HarnessBackend(HostedUserStateBackend):
    def __init__(self) -> None:
        self._runtime_dynamodb = FakeRuntimeDynamo()
        self._runtime_table_name = "runtime"
        self.contexts = {
            "token-a": ("group", "app", "user-a"),
            "token-b": ("group", "app", "user-b"),
        }

    def _consume_runtime_request(self, token: str) -> tuple[str, str, str]:
        try:
            return self.contexts[token]
        except KeyError as exc:
            raise AssertionError(f"unexpected token {token}") from exc


class HostedUserStateBackendTest(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = HarnessBackend()

    def test_same_key_is_private_per_runtime_session_user(self) -> None:
        self.backend.set_runtime_user_state("token-a", "progress", {"scene": "a"})
        self.backend.set_runtime_user_state("token-b", "progress", {"scene": "b"})

        self.assertEqual(
            self.backend.get_runtime_user_state("token-a", "progress")["value"],
            {"scene": "a"},
        )
        self.assertEqual(
            self.backend.get_runtime_user_state("token-b", "progress")["value"],
            {"scene": "b"},
        )

        keys = set(self.backend._runtime_dynamodb.items)
        self.assertIn(("GROUP#group#APP#app", "USER#user-a#STATE#progress"), keys)
        self.assertIn(("GROUP#group#APP#app", "USER#user-b#STATE#progress"), keys)
        self.assertNotIn(("GROUP#group#APP#app", "STATE#progress"), keys)

    def test_shared_state_row_is_not_reinterpreted_as_user_state(self) -> None:
        shared_item = {
            "pk": {"S": "GROUP#group#APP#app"},
            "sk": {"S": "STATE#progress"},
            "entity": {"S": "runtime_state"},
            "key": {"S": "progress"},
            "value_json": {"S": json.dumps({"scope": "shared"})},
            "updated_at": {"S": "2026-09-06T08:00:00Z"},
        }
        self.backend._runtime_dynamodb.items[
            ("GROUP#group#APP#app", "STATE#progress")
        ] = shared_item

        with self.assertRaises(ApiProblem) as caught:
            self.backend.get_runtime_user_state("token-a", "progress")
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "state_not_found")

    def test_delete_only_removes_current_users_private_key(self) -> None:
        self.backend.set_runtime_user_state("token-a", "progress", 1)
        self.backend.set_runtime_user_state("token-b", "progress", 2)

        self.backend.delete_runtime_user_state("token-a", "progress")

        with self.assertRaises(ApiProblem):
            self.backend.get_runtime_user_state("token-a", "progress")
        self.assertEqual(
            self.backend.get_runtime_user_state("token-b", "progress")["value"],
            2,
        )


if __name__ == "__main__":
    unittest.main()
