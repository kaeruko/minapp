from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import abuse_entry  # noqa: E402
import hosted_shop_handler  # noqa: E402
from aws_backend import _string_attr  # noqa: E402
from hosted_group_settings import rename_group  # noqa: E402

GROUP_ID = "2" * 32
OWNER_ID = "3" * 32
MEMBER_ID = "4" * 32
INVITE_HASH = "5" * 64


class FakeDynamo:
    def __init__(self) -> None:
        self.transactions: list[list[dict[str, Any]]] = []

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        self.transactions.append(TransactItems)


class FakeBackend:
    def __init__(self) -> None:
        self._table_name = "hosted-data"
        self._dynamodb = FakeDynamo()
        self.owner = SimpleNamespace(user_id=OWNER_ID)
        self.group = {
            "pk": _string_attr(f"GROUP#{GROUP_ID}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("group"),
            "group_id": _string_attr(GROUP_ID),
            "name": _string_attr("わんわん"),
            "visibility": _string_attr("private"),
            "invite_hash": _string_attr(INVITE_HASH),
        }
        self.group_memberships = [
            self._membership(OWNER_ID, "owner"),
            self._membership(MEMBER_ID, "member"),
        ]
        self.user_memberships = {
            OWNER_ID: self._user_membership(OWNER_ID, "owner"),
            MEMBER_ID: self._user_membership(MEMBER_ID, "member"),
        }
        self.invite = {
            "pk": _string_attr(f"INVITE#{INVITE_HASH}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("group_invite"),
            "group_id": _string_attr(GROUP_ID),
            "group_name": _string_attr("わんわん"),
        }

    def _membership(self, user_id: str, role: str) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"GROUP#{GROUP_ID}"),
            "sk": _string_attr(f"MEMBER#{user_id}"),
            "entity": _string_attr("membership"),
            "group_id": _string_attr(GROUP_ID),
            "group_name": _string_attr("わんわん"),
            "user_id": _string_attr(user_id),
            "role": _string_attr(role),
            "status": _string_attr("active"),
        }

    def _user_membership(self, user_id: str, role: str) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"USER#{user_id}"),
            "sk": _string_attr(f"GROUP#{GROUP_ID}"),
            "entity": _string_attr("membership"),
            "group_id": _string_attr(GROUP_ID),
            "group_name": _string_attr("わんわん"),
            "user_id": _string_attr(user_id),
            "role": _string_attr(role),
            "status": _string_attr("active"),
        }

    def _user_by_auth_subject(self, auth_subject: str) -> SimpleNamespace:
        if auth_subject != "owner-subject":
            raise AssertionError(auth_subject)
        return self.owner

    def _require_owner_group(self, user_id: str, group_id: str) -> dict[str, Any]:
        if user_id != OWNER_ID or group_id != GROUP_ID:
            raise AssertionError((user_id, group_id))
        return self.group

    def _membership_items_for_group(self, group_id: str) -> list[dict[str, Any]]:
        if group_id != GROUP_ID:
            raise AssertionError(group_id)
        return self.group_memberships

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None:
        if pk == f"INVITE#{INVITE_HASH}" and sk == "META":
            return self.invite
        if pk.startswith("USER#") and sk == f"GROUP#{GROUP_ID}":
            return self.user_memberships.get(pk.removeprefix("USER#"))
        raise AssertionError((pk, sk))


def _event(method: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "rawPath": path,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
        "requestContext": {
            "http": {"method": method},
            "domainName": "girls-api.example.com",
            "authorizer": {"jwt": {"claims": {"sub": "owner-subject"}}},
        },
    }


class HostedGroupSettingsTests(unittest.TestCase):
    def test_rename_updates_group_invite_and_both_membership_copies_atomically(self) -> None:
        backend = FakeBackend()
        result = rename_group(backend, "owner-subject", GROUP_ID, "しばちゃん部")

        self.assertEqual(result["group_id"], GROUP_ID)
        self.assertEqual(result["name"], "しばちゃん部")
        self.assertEqual(result["role"], "owner")
        self.assertEqual(len(backend._dynamodb.transactions), 1)

        operations = backend._dynamodb.transactions[0]
        self.assertEqual(len(operations), 6)
        replaced = [operation["Put"]["Item"] for operation in operations]
        self.assertEqual(replaced[0]["name"], _string_attr("しばちゃん部"))
        self.assertEqual(replaced[1]["group_name"], _string_attr("しばちゃん部"))
        for item in replaced[2:]:
            self.assertEqual(item["group_name"], _string_attr("しばちゃん部"))
        for operation in operations:
            self.assertEqual(
                operation["Put"]["ConditionExpression"],
                "attribute_exists(pk) AND attribute_exists(sk)",
            )

    def test_same_name_is_idempotent_without_write(self) -> None:
        backend = FakeBackend()
        result = rename_group(backend, "owner-subject", GROUP_ID, "わんわん")
        self.assertEqual(result["name"], "わんわん")
        self.assertEqual(backend._dynamodb.transactions, [])

    def test_patch_route_requires_only_name_and_returns_updated_group(self) -> None:
        backend = FakeBackend()
        with patch.object(hosted_shop_handler, "_shared_backend", return_value=backend):
            response = hosted_shop_handler.lambda_handler(
                _event("PATCH", f"/hosted/groups/{GROUP_ID}", {"name": "新しい名前"}),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["group_id"], GROUP_ID)
        self.assertEqual(payload["name"], "新しい名前")
        self.assertEqual(len(backend._dynamodb.transactions), 1)

    def test_deployed_hosted_entry_routes_group_patch_to_shop_handler(self) -> None:
        backend = FakeBackend()
        with patch.object(hosted_shop_handler, "_shared_backend", return_value=backend):
            response = abuse_entry.hosted_lambda_handler(
                _event("PATCH", f"/hosted/groups/{GROUP_ID}", {"name": "みんなのアトリエ"}),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["group_id"], GROUP_ID)
        self.assertEqual(payload["name"], "みんなのアトリエ")
        self.assertEqual(len(backend._dynamodb.transactions), 1)

    def test_patch_route_rejects_unknown_fields_before_write(self) -> None:
        backend = FakeBackend()
        with patch.object(hosted_shop_handler, "_shared_backend", return_value=backend):
            response = hosted_shop_handler.lambda_handler(
                _event(
                    "PATCH",
                    f"/hosted/groups/{GROUP_ID}",
                    {"name": "新しい名前", "visibility": "public"},
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(backend._dynamodb.transactions, [])


if __name__ == "__main__":
    unittest.main()
