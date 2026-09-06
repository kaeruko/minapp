from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from hosted_preview_state_backend import HostedPreviewStateBackend  # noqa: E402


class FakeDynamo:
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


class HarnessBackend(HostedPreviewStateBackend):
    def __init__(self) -> None:
        self._dynamodb = FakeDynamo()
        self._table_name = "metadata"
        self._runtime_dynamodb = FakeDynamo()
        self._runtime_table_name = "runtime"
        self.contexts = {
            "preview": ("group", "app", "user"),
            "published": ("group", "app", "user"),
        }
        self.sessions = {
            "preview": {
                "preview_state_id": {"S": "a" * 64},
                "preview_state_ttl_epoch": {"N": "1999999999"},
            },
            "published": {},
        }

    def _consume_runtime_request(self, token: str) -> tuple[str, str, str]:
        return self.contexts[token]

    def _runtime_session_item(self, token: str) -> dict[str, Any] | None:
        return self.sessions.get(token)


class HostedPreviewStateBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = HarnessBackend()

    def test_preview_shared_and_user_state_use_ephemeral_namespace(self) -> None:
        self.backend.set_preview_runtime_state(
            "preview",
            "chapter",
            {"scene": 2},
            user_state=False,
        )
        self.backend.set_runtime_user_state(
            "preview",
            "save",
            {"scene": 3},
        )

        keys = set(self.backend._dynamodb.items)
        self.assertIn(("PREVIEWSTATE#" + "a" * 64, "STATE#chapter"), keys)
        self.assertIn(
            ("PREVIEWSTATE#" + "a" * 64, "USER#user#STATE#save"),
            keys,
        )
        self.assertEqual(self.backend._runtime_dynamodb.items, {})
        self.assertEqual(
            self.backend.get_preview_runtime_state(
                "preview",
                "chapter",
                user_state=False,
            )["value"],
            {"scene": 2},
        )
        self.assertEqual(
            self.backend.get_runtime_user_state("preview", "save")["value"],
            {"scene": 3},
        )

    def test_published_user_state_keeps_existing_persistent_namespace(self) -> None:
        self.backend.set_runtime_user_state("published", "save", 5)
        self.assertIn(
            ("GROUP#group#APP#app", "USER#user#STATE#save"),
            self.backend._runtime_dynamodb.items,
        )
        self.assertEqual(self.backend._dynamodb.items, {})

    def test_partial_preview_scope_fails_closed(self) -> None:
        self.backend.sessions["preview"] = {
            "preview_state_id": {"S": "a" * 64},
        }
        with self.assertRaises(RuntimeError):
            self.backend.is_preview_runtime_session("preview")


if __name__ == "__main__":
    unittest.main()
