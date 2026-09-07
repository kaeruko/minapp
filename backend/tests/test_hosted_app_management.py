from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_app_management import record_launch  # noqa: E402


class DynamoCapture:
    def __init__(self) -> None:
        self.transactions: list[list[dict[str, Any]]] = []

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        self.transactions.append(TransactItems)


class BackendHarness:
    def __init__(self) -> None:
        self._table_name = "hosted-data"
        self._dynamodb = DynamoCapture()


class HostedAppManagementTests(unittest.TestCase):
    def test_record_launch_aliases_reserved_month_attribute(self) -> None:
        backend = BackendHarness()

        record_launch(
            backend,
            group_id="2" * 32,
            app_id="3" * 32,
            user_id="4" * 32,
        )

        self.assertEqual(len(backend._dynamodb.transactions), 1)
        updates = backend._dynamodb.transactions[0]
        self.assertEqual(len(updates), 3)

        month_update = updates[1]["Update"]
        self.assertEqual(month_update["ExpressionAttributeNames"], {"#month": "month"})
        self.assertIn("#month = if_not_exists(#month, :month)", month_update["UpdateExpression"])
        self.assertNotIn("month = if_not_exists(month, :month)", month_update["UpdateExpression"])
        self.assertEqual(month_update["ExpressionAttributeValues"][":month"]["S"], month_update["Key"]["sk"]["S"].removeprefix("MONTH#"))

        self.assertNotIn("ExpressionAttributeNames", updates[0]["Update"])
        self.assertNotIn("ExpressionAttributeNames", updates[2]["Update"])


if __name__ == "__main__":
    unittest.main()
