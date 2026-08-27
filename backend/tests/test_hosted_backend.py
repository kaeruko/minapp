from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_backend import HostedAwsBackend  # noqa: E402


class FakeAwsError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeCognito:
    def __init__(self) -> None:
        self.users: dict[str, dict[str, Any]] = {}
        self.counter = 0

    def admin_create_user(
        self,
        *,
        UserPoolId: str,
        Username: str,
        TemporaryPassword: str,
        MessageAction: str,
    ) -> dict[str, Any]:
        del UserPoolId
        if MessageAction != "SUPPRESS":
            raise AssertionError(MessageAction)
        if Username in self.users:
            raise FakeAwsError("UsernameExistsException")
        self.counter += 1
        self.users[Username] = {
            "sub": f"hosted-sub-{self.counter}",
            "password": TemporaryPassword,
            "temporary": True,
        }
        return {}

    def admin_set_user_password(
        self,
        *,
        UserPoolId: str,
        Username: str,
        Password: str,
        Permanent: bool,
    ) -> None:
        del UserPoolId
        user = self.users.get(Username)
        if user is None:
            raise FakeAwsError("UserNotFoundException")
        user["password"] = Password
        user["temporary"] = not Permanent

    def admin_get_user(self, *, UserPoolId: str, Username: str) -> dict[str, Any]:
        del UserPoolId
        user = self.users.get(Username)
        if user is None:
            raise FakeAwsError("UserNotFoundException")
        return {
            "Username": Username,
            "UserAttributes": [{"Name": "sub", "Value": user["sub"]}],
        }

    def admin_delete_user(self, *, UserPoolId: str, Username: str) -> None:
        del UserPoolId
        if Username not in self.users:
            raise FakeAwsError("UserNotFoundException")
        del self.users[Username]

    def initiate_auth(
        self,
        *,
        ClientId: str,
        AuthFlow: str,
        AuthParameters: dict[str, str],
    ) -> dict[str, Any]:
        del ClientId
        if AuthFlow != "USER_PASSWORD_AUTH":
            raise AssertionError(AuthFlow)
        username = AuthParameters["USERNAME"]
        password = AuthParameters["PASSWORD"]
        user = self.users.get(username)
        if user is None or user["password"] != password:
            raise FakeAwsError("NotAuthorizedException")
        if user["temporary"]:
            raise AssertionError("Hosted users must have permanent passwords")
        return {
            "AuthenticationResult": {
                "AccessToken": f"access-{username}",
                "RefreshToken": f"refresh-{username}",
                "TokenType": "Bearer",
                "ExpiresIn": 3600,
            }
        }


class FakeDynamoDb:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}

    @staticmethod
    def _s(attribute: dict[str, str]) -> str:
        return attribute["S"]

    def get_item(
        self,
        *,
        TableName: str,
        Key: dict[str, dict[str, str]],
        ConsistentRead: bool,
    ) -> dict[str, Any]:
        del TableName, ConsistentRead
        key = (self._s(Key["pk"]), self._s(Key["sk"]))
        item = self.items.get(key)
        return {} if item is None else {"Item": item}

    def query(
        self,
        *,
        TableName: str,
        KeyConditionExpression: str,
        ExpressionAttributeValues: dict[str, dict[str, str]],
        ConsistentRead: bool,
    ) -> dict[str, Any]:
        del TableName, ConsistentRead
        if "begins_with" not in KeyConditionExpression:
            raise AssertionError(KeyConditionExpression)
        pk = self._s(ExpressionAttributeValues[":pk"])
        prefix_keys = [key for key in ExpressionAttributeValues if key != ":pk"]
        if len(prefix_keys) != 1:
            raise AssertionError(ExpressionAttributeValues)
        prefix = self._s(ExpressionAttributeValues[prefix_keys[0]])
        return {
            "Items": [
                item
                for (item_pk, item_sk), item in self.items.items()
                if item_pk == pk and item_sk.startswith(prefix)
            ]
        }

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        for operation in TransactItems:
            if "Put" in operation:
                request = operation["Put"]
                item = request["Item"]
                key = (self._s(item["pk"]), self._s(item["sk"]))
                condition = request.get("ConditionExpression")
                if condition == "attribute_not_exists(pk)" and key in self.items:
                    raise FakeAwsError("TransactionCanceledException")
                if condition == "attribute_exists(pk)" and key not in self.items:
                    raise FakeAwsError("TransactionCanceledException")
            elif "Delete" in operation:
                request = operation["Delete"]
                key = (self._s(request["Key"]["pk"]), self._s(request["Key"]["sk"]))
                if request.get("ConditionExpression") == "attribute_exists(pk)" and key not in self.items:
                    raise FakeAwsError("TransactionCanceledException")
            else:
                raise AssertionError(operation)

        for operation in TransactItems:
            if "Put" in operation:
                item = operation["Put"]["Item"]
                key = (self._s(item["pk"]), self._s(item["sk"]))
                self.items[key] = item
            else:
                request = operation["Delete"]
                key = (self._s(request["Key"]["pk"]), self._s(request["Key"]["sk"]))
                del self.items[key]


class HostedBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.backend = HostedAwsBackend(
            cognito=self.cognito,
            dynamodb=self.dynamo,
            user_pool_id="pool",
            app_client_id="client",
            table_name="table",
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"]

    def test_register_creates_permanent_hosted_user(self) -> None:
        subject = self._register("alice")
        self.assertFalse(self.cognito.users["alice"]["temporary"])
        me = self.backend.me(subject)
        self.assertEqual(me["user"]["login_id"], "alice")
        self.assertEqual(me["user"]["role"], "user")
        self.assertEqual(me["groups"], [])
        logged_in = self.backend.login("alice", "secret12")
        self.assertEqual(logged_in["state"], "authenticated")

    def test_duplicate_login_id_is_rejected(self) -> None:
        self._register("alice")
        with self.assertRaises(ApiProblem) as caught:
            self.backend.register("alice", "secret34")
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "login_id_conflict")

    def test_owner_can_invite_member_and_member_can_leave(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "月影荘")
        invite = self.backend.create_invite(alice, group["group_id"])

        joined = self.backend.join_group(bob, invite["code"])
        self.assertEqual(joined["role"], "member")
        self.assertEqual(joined["name"], "月影荘")
        members = self.backend.list_members(alice, group["group_id"])
        self.assertEqual({member["role"] for member in members}, {"owner", "member"})

        self.backend.leave_group(bob, group["group_id"])
        self.assertEqual(
            self.backend.list_groups(bob),
            [],
        )

    def test_rotating_invite_invalidates_old_code(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "秘密基地")
        old_invite = self.backend.create_invite(alice, group["group_id"])
        new_invite = self.backend.create_invite(alice, group["group_id"])

        with self.assertRaises(ApiProblem) as caught:
            self.backend.join_group(bob, old_invite["code"])
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "invite_not_found")

        joined = self.backend.join_group(bob, new_invite["code"])
        self.assertEqual(joined["group_id"], group["group_id"])

    def test_revoked_invite_cannot_be_used(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "創作部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.revoke_invite(alice, group["group_id"])

        with self.assertRaises(ApiProblem) as caught:
            self.backend.join_group(bob, invite["code"])
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "invite_not_found")

    def test_owner_cannot_leave_group(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "小説部屋")
        with self.assertRaises(ApiProblem) as caught:
            self.backend.leave_group(alice, group["group_id"])
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "owner_cannot_leave")

    def test_owner_can_remove_member_but_not_owner(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "設定資料室")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])

        bob_id = self.backend.me(bob)["user"]["user_id"]
        self.backend.remove_member(alice, group["group_id"], bob_id)
        self.assertEqual(self.backend.list_groups(bob), [])

        alice_id = self.backend.me(alice)["user"]["user_id"]
        with self.assertRaises(ApiProblem) as caught:
            self.backend.remove_member(alice, group["group_id"], alice_id)
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "owner_removal_not_supported")


if __name__ == "__main__":
    unittest.main()
