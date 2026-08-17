from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import AwsBackend, _User  # noqa: E402
from errors import ApiProblem  # noqa: E402


class FakeAwsError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeCognito:
    def __init__(self) -> None:
        self.users: dict[str, dict[str, Any]] = {}
        self.sessions: dict[str, str] = {}
        self.counter = 0

    def add_user(self, username: str, password: str, *, temporary: bool) -> str:
        self.counter += 1
        subject = f"sub-{self.counter}"
        self.users[username] = {"sub": subject, "password": password, "temporary": temporary}
        return subject

    def initiate_auth(self, *, ClientId: str, AuthFlow: str, AuthParameters: dict[str, str]) -> dict[str, Any]:
        del ClientId
        if AuthFlow != "USER_PASSWORD_AUTH":
            raise AssertionError(AuthFlow)
        username = AuthParameters["USERNAME"]
        password = AuthParameters["PASSWORD"]
        user = self.users.get(username)
        if user is None or user["password"] != password:
            raise FakeAwsError("NotAuthorizedException")
        if user["temporary"]:
            session = f"session-{username}"
            self.sessions[session] = username
            return {"ChallengeName": "NEW_PASSWORD_REQUIRED", "Session": session}
        return {"AuthenticationResult": {"AccessToken": f"access-{username}", "RefreshToken": f"refresh-{username}", "TokenType": "Bearer", "ExpiresIn": 3600}}

    def respond_to_auth_challenge(self, *, ClientId: str, ChallengeName: str, Session: str, ChallengeResponses: dict[str, str]) -> dict[str, Any]:
        del ClientId
        if ChallengeName != "NEW_PASSWORD_REQUIRED":
            raise AssertionError(ChallengeName)
        username = self.sessions.pop(Session, None)
        if username is None or username != ChallengeResponses["USERNAME"]:
            raise FakeAwsError("NotAuthorizedException")
        self.users[username]["password"] = ChallengeResponses["NEW_PASSWORD"]
        self.users[username]["temporary"] = False
        return {"AuthenticationResult": {"AccessToken": f"access-{username}", "RefreshToken": f"refresh-{username}", "TokenType": "Bearer", "ExpiresIn": 3600}}

    def admin_create_user(self, *, UserPoolId: str, Username: str, TemporaryPassword: str, MessageAction: str) -> dict[str, Any]:
        del UserPoolId
        if MessageAction != "SUPPRESS":
            raise AssertionError(MessageAction)
        if Username in self.users:
            raise FakeAwsError("UsernameExistsException")
        self.add_user(Username, TemporaryPassword, temporary=True)
        return {}

    def admin_get_user(self, *, UserPoolId: str, Username: str) -> dict[str, Any]:
        del UserPoolId
        user = self.users.get(Username)
        if user is None:
            raise FakeAwsError("UserNotFoundException")
        return {"Username": Username, "UserAttributes": [{"Name": "sub", "Value": user["sub"]}]}

    def admin_delete_user(self, *, UserPoolId: str, Username: str) -> None:
        del UserPoolId
        if Username not in self.users:
            raise FakeAwsError("UserNotFoundException")
        del self.users[Username]

    def admin_set_user_password(self, *, UserPoolId: str, Username: str, Password: str, Permanent: bool) -> None:
        del UserPoolId
        user = self.users.get(Username)
        if user is None:
            raise FakeAwsError("UserNotFoundException")
        user["password"] = Password
        user["temporary"] = not Permanent


class FakeDynamoDb:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}

    @staticmethod
    def _s(attribute: dict[str, str]) -> str:
        return attribute["S"]

    def get_item(self, *, TableName: str, Key: dict[str, dict[str, str]], ConsistentRead: bool) -> dict[str, Any]:
        del TableName, ConsistentRead
        key = (self._s(Key["pk"]), self._s(Key["sk"]))
        item = self.items.get(key)
        return {} if item is None else {"Item": item}

    def query(self, *, TableName: str, KeyConditionExpression: str, ExpressionAttributeValues: dict[str, dict[str, str]], ConsistentRead: bool) -> dict[str, Any]:
        del TableName, ConsistentRead
        if "begins_with" not in KeyConditionExpression:
            raise AssertionError(KeyConditionExpression)
        pk = self._s(ExpressionAttributeValues[":pk"])
        prefix_key = ":group_prefix" if ":group_prefix" in ExpressionAttributeValues else ":member_prefix"
        prefix = self._s(ExpressionAttributeValues[prefix_key])
        results = [item for (item_pk, item_sk), item in self.items.items() if item_pk == pk and item_sk.startswith(prefix)]
        return {"Items": results}

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        for operation in TransactItems:
            if "Put" in operation:
                request = operation["Put"]
                item = request["Item"]
                key = (self._s(item["pk"]), self._s(item["sk"]))
                if request.get("ConditionExpression") == "attribute_not_exists(pk)" and key in self.items:
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


class AwsBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.backend = AwsBackend(cognito=self.cognito, dynamodb=self.dynamo, user_pool_id="pool", app_client_id="client", table_name="table")
        self.teacher_subject = self.cognito.add_user("teacher-demo", "TeacherPass1", temporary=False)
        self.teacher = _User(user_id="1" * 32, auth_subject=self.teacher_subject, login_id="teacher-demo", role="teacher", status="active")
        self.backend._transact_put_new([self.backend._auth_item(self.teacher), self.backend._user_item(self.teacher)])

    def test_temporary_password_login_requires_change(self) -> None:
        self.cognito.add_user("student-demo", "Temporary1", temporary=True)
        result = self.backend.login("student-demo", "Temporary1")
        self.assertEqual(result["state"], "new_password_required")
        changed = self.backend.complete_new_password("student-demo", "PermanentPass1", result["session"])
        self.assertEqual(changed["state"], "authenticated")

    def test_invalid_credentials_are_generic(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            self.backend.login("teacher-demo", "wrong-password")
        self.assertEqual(caught.exception.status_code, 401)
        self.assertEqual(caught.exception.error, "invalid_credentials")

    def test_teacher_can_create_group_and_list_it(self) -> None:
        group = self.backend.create_group(self.teacher_subject, "6年2組")
        groups = self.backend.list_groups(self.teacher_subject)
        self.assertEqual(groups, [{"group_id": group["group_id"], "name": "6年2組", "role": "teacher", "status": "active"}])

    def test_teacher_can_create_student_reset_password_and_remove_membership(self) -> None:
        group = self.backend.create_group(self.teacher_subject, "プログラミング教室")
        created = self.backend.create_student(self.teacher_subject, group["group_id"])
        self.assertTrue(created["login_id"].startswith("student-"))
        members = self.backend.list_members(self.teacher_subject, group["group_id"])
        self.assertEqual({member["role"] for member in members}, {"teacher", "student"})
        reset = self.backend.reset_student_password(self.teacher_subject, created["user_id"])
        self.assertEqual(reset["login_id"], created["login_id"])
        self.assertNotEqual(reset["temporary_password"], created["temporary_password"])
        self.backend.remove_member(self.teacher_subject, group["group_id"], created["user_id"])
        members_after = self.backend.list_members(self.teacher_subject, group["group_id"])
        self.assertEqual([member["role"] for member in members_after], ["teacher"])

    def test_student_cannot_create_group(self) -> None:
        group = self.backend.create_group(self.teacher_subject, "教室")
        created = self.backend.create_student(self.teacher_subject, group["group_id"])
        student = self.backend._user_by_id(created["user_id"])
        with self.assertRaises(ApiProblem) as caught:
            self.backend.create_group(student.auth_subject, "勝手なグループ")
        self.assertEqual(caught.exception.status_code, 403)

    def test_teacher_cannot_manage_student_from_unrelated_group(self) -> None:
        group = self.backend.create_group(self.teacher_subject, "教室A")
        created = self.backend.create_student(self.teacher_subject, group["group_id"])
        other_subject = self.cognito.add_user("teacher-other", "TeacherPass2", temporary=False)
        other_teacher = _User(user_id="2" * 32, auth_subject=other_subject, login_id="teacher-other", role="teacher", status="active")
        self.backend._transact_put_new([self.backend._auth_item(other_teacher), self.backend._user_item(other_teacher)])
        with self.assertRaises(ApiProblem) as caught:
            self.backend.reset_student_password(other_subject, created["user_id"])
        self.assertEqual(caught.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
