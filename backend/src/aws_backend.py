from __future__ import annotations

import os
import secrets
import uuid
from dataclasses import dataclass
from typing import Any

from errors import ApiProblem


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


def _string_attr(value: str) -> dict[str, str]:
    if not isinstance(value, str) or not value:
        raise ValueError("DynamoDB string attributes must be non-empty strings")
    return {"S": value}


def _item_string(item: dict[str, Any], key: str) -> str:
    raw = item.get(key)
    if not isinstance(raw, dict):
        raise RuntimeError(f"DynamoDB item is missing string attribute {key!r}")
    value = raw.get("S")
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a non-empty string")
    return value


def _aws_error_code(exc: Exception) -> str | None:
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return None
    error = response.get("Error")
    if not isinstance(error, dict):
        return None
    code = error.get("Code")
    return code if isinstance(code, str) else None


def _new_login_id() -> str:
    return f"student-{secrets.token_hex(4)}"


_TEMPORARY_PASSWORD_ALPHABET = "23456789"
_TEMPORARY_PASSWORD_LENGTH = 8


def _new_temporary_password() -> str:
    return "".join(
        secrets.choice(_TEMPORARY_PASSWORD_ALPHABET)
        for _ in range(_TEMPORARY_PASSWORD_LENGTH)
    )


@dataclass(frozen=True)
class _User:
    user_id: str
    auth_subject: str
    login_id: str
    role: str
    status: str


class AwsBackend:
    def __init__(
        self,
        *,
        cognito: Any,
        dynamodb: Any,
        user_pool_id: str,
        app_client_id: str,
        table_name: str,
    ) -> None:
        self._cognito = cognito
        self._dynamodb = dynamodb
        self._user_pool_id = user_pool_id
        self._app_client_id = app_client_id
        self._table_name = table_name

    @classmethod
    def from_environment(cls) -> "AwsBackend":
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required outside the AWS Lambda runtime. "
                "Install the development requirements explicitly."
            ) from exc

        return cls(
            cognito=boto3.client("cognito-idp"),
            dynamodb=boto3.client("dynamodb"),
            user_pool_id=_required_env("USER_POOL_ID"),
            app_client_id=_required_env("USER_POOL_CLIENT_ID"),
            table_name=_required_env("DATA_TABLE_NAME"),
        )

    def login(self, login_id: str, password: str) -> dict[str, Any]:
        try:
            response = self._cognito.initiate_auth(
                ClientId=self._app_client_id,
                AuthFlow="USER_PASSWORD_AUTH",
                AuthParameters={"USERNAME": login_id, "PASSWORD": password},
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code in {"NotAuthorizedException", "UserNotFoundException"}:
                raise ApiProblem(
                    401,
                    "invalid_credentials",
                    "IDまたはパスワードが正しくありません。",
                ) from exc
            if code == "PasswordResetRequiredException":
                raise ApiProblem(
                    409,
                    "password_reset_required",
                    "先生による仮パスワードの再発行が必要です。",
                ) from exc
            raise

        return self._auth_response(response, expected_login_id=login_id)

    def complete_new_password(
        self,
        login_id: str,
        new_password: str,
        session: str,
    ) -> dict[str, Any]:
        try:
            response = self._cognito.respond_to_auth_challenge(
                ClientId=self._app_client_id,
                ChallengeName="NEW_PASSWORD_REQUIRED",
                Session=session,
                ChallengeResponses={
                    "USERNAME": login_id,
                    "NEW_PASSWORD": new_password,
                },
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code in {
                "NotAuthorizedException",
                "CodeMismatchException",
                "ExpiredCodeException",
            }:
                raise ApiProblem(
                    401,
                    "invalid_or_expired_session",
                    "初回パスワード変更のセッションが無効または期限切れです。",
                ) from exc
            if code == "InvalidPasswordException":
                raise ApiProblem(
                    400,
                    "invalid_password",
                    "新しいパスワードがパスワードポリシーを満たしていません。",
                ) from exc
            raise

        return self._auth_response(response, expected_login_id=login_id)

    def _auth_response(
        self,
        response: dict[str, Any],
        *,
        expected_login_id: str,
    ) -> dict[str, Any]:
        challenge = response.get("ChallengeName")
        if challenge is not None:
            if challenge != "NEW_PASSWORD_REQUIRED":
                raise RuntimeError(f"Unsupported Cognito authentication challenge: {challenge!r}")
            session = response.get("Session")
            if not isinstance(session, str) or not session:
                raise RuntimeError("Cognito NEW_PASSWORD_REQUIRED response has no session")
            return {
                "state": "new_password_required",
                "login_id": expected_login_id,
                "session": session,
            }

        result = response.get("AuthenticationResult")
        if not isinstance(result, dict):
            raise RuntimeError("Cognito response contains neither a challenge nor authentication result")

        access_token = result.get("AccessToken")
        token_type = result.get("TokenType")
        expires_in = result.get("ExpiresIn")
        if not isinstance(access_token, str) or not access_token:
            raise RuntimeError("Cognito authentication result has no access token")
        if not isinstance(token_type, str) or not token_type:
            raise RuntimeError("Cognito authentication result has no token type")
        if not isinstance(expires_in, int) or expires_in <= 0:
            raise RuntimeError("Cognito authentication result has an invalid expiry")

        payload: dict[str, Any] = {
            "state": "authenticated",
            "access_token": access_token,
            "token_type": token_type,
            "expires_in": expires_in,
        }

        refresh_token = result.get("RefreshToken")
        if refresh_token is not None:
            if not isinstance(refresh_token, str) or not refresh_token:
                raise RuntimeError("Cognito refresh token has an invalid value")
            payload["refresh_token"] = refresh_token

        return payload

    def me(self, auth_subject: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        return {
            "user": self._public_user(user),
            "groups": self._list_groups_for_user(user.user_id),
        }

    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        return self._list_groups_for_user(user.user_id)

    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_role(teacher, "teacher")

        group_id = uuid.uuid4().hex
        group_pk = f"GROUP#{group_id}"
        member_sk = f"MEMBER#{teacher.user_id}"
        user_pk = f"USER#{teacher.user_id}"
        membership_sk = f"GROUP#{group_id}"

        group_item = {
            "pk": _string_attr(group_pk),
            "sk": _string_attr("META"),
            "entity": _string_attr("group"),
            "group_id": _string_attr(group_id),
            "name": _string_attr(name),
            "created_by": _string_attr(teacher.user_id),
        }
        group_member_item = self._membership_item(
            pk=group_pk,
            sk=member_sk,
            user=teacher,
            group_id=group_id,
            group_name=name,
            role="teacher",
        )
        user_membership_item = self._membership_item(
            pk=user_pk,
            sk=membership_sk,
            user=teacher,
            group_id=group_id,
            group_name=name,
            role="teacher",
        )

        self._transact_put_new([group_item, group_member_item, user_membership_item])

        return {
            "group_id": group_id,
            "name": name,
            "role": "teacher",
            "status": "active",
        }

    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_teacher_membership(teacher.user_id, group_id)

        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :member_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}"),
                ":member_prefix": _string_attr("MEMBER#"),
            },
            ConsistentRead=True,
        )
        items = self._query_items(response)
        members: list[dict[str, Any]] = []
        for item in items:
            members.append(
                {
                    "user_id": _item_string(item, "user_id"),
                    "login_id": _item_string(item, "login_id"),
                    "role": _item_string(item, "role"),
                    "status": _item_string(item, "status"),
                }
            )
        members.sort(key=lambda member: (member["role"], member["login_id"]))
        return members

    def create_student(
        self,
        auth_subject: str,
        group_id: str,
        login_id: str | None = None,
    ) -> dict[str, Any]:
        teacher = self._user_by_auth_subject(auth_subject)
        group_name = self._require_teacher_membership(teacher.user_id, group_id)

        if login_id is not None:
            if not isinstance(login_id, str):
                raise TypeError("login_id must be a string or None")
            if not login_id:
                raise ValueError("login_id must not be empty")
        requested_login_id = login_id
        login_id = _new_login_id() if login_id is None else login_id
        temporary_password = _new_temporary_password()
        user_id = uuid.uuid4().hex

        try:
            self._cognito.admin_create_user(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                TemporaryPassword=temporary_password,
                MessageAction="SUPPRESS",
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code == "UsernameExistsException":
                message = (
                    "指定したIDはすでに使われています。別のIDを入力してください。"
                    if requested_login_id is not None
                    else "生成したIDが既存ユーザーと衝突しました。処理は停止しました。"
                )
                raise ApiProblem(409, "login_id_conflict", message) from exc
            raise

        try:
            auth_subject_new = self._cognito_subject(login_id)
            student = _User(
                user_id=user_id,
                auth_subject=auth_subject_new,
                login_id=login_id,
                role="student",
                status="active",
            )
            items = [
                self._auth_item(student),
                self._user_item(student),
                self._membership_item(
                    pk=f"USER#{user_id}",
                    sk=f"GROUP#{group_id}",
                    user=student,
                    group_id=group_id,
                    group_name=group_name,
                    role="student",
                ),
                self._membership_item(
                    pk=f"GROUP#{group_id}",
                    sk=f"MEMBER#{user_id}",
                    user=student,
                    group_id=group_id,
                    group_name=group_name,
                    role="student",
                ),
            ]
            self._transact_put_new(items)
        except Exception as original_exc:
            try:
                self._cognito.admin_delete_user(
                    UserPoolId=self._user_pool_id,
                    Username=login_id,
                )
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Student creation failed after Cognito user creation, "
                    "and cleanup of the Cognito user also failed."
                ) from cleanup_exc
            raise original_exc

        return {
            "user_id": user_id,
            "login_id": login_id,
            "temporary_password": temporary_password,
            "group_id": group_id,
            "role": "student",
        }

    def reset_student_password(
        self,
        auth_subject: str,
        user_id: str,
    ) -> dict[str, Any]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_role(teacher, "teacher")
        student = self._user_by_id(user_id)
        self._require_role(student, "student")
        self._require_shared_teacher_group(teacher.user_id, student.user_id)

        temporary_password = _new_temporary_password()
        try:
            self._cognito.admin_set_user_password(
                UserPoolId=self._user_pool_id,
                Username=student.login_id,
                Password=temporary_password,
                Permanent=False,
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code == "UserNotFoundException":
                raise RuntimeError(
                    f"DynamoDB user {student.user_id} has no matching Cognito user"
                ) from exc
            raise

        return {
            "user_id": student.user_id,
            "login_id": student.login_id,
            "temporary_password": temporary_password,
        }

    def remove_member(
        self,
        auth_subject: str,
        group_id: str,
        user_id: str,
    ) -> None:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_teacher_membership(teacher.user_id, group_id)

        target_membership = self._get_item(
            pk=f"GROUP#{group_id}",
            sk=f"MEMBER#{user_id}",
        )
        if target_membership is None:
            raise ApiProblem(404, "member_not_found", "指定されたメンバーは存在しません。")
        role = _item_string(target_membership, "role")
        if role != "student":
            raise ApiProblem(
                409,
                "teacher_removal_not_supported",
                "MVPでは先生の所属解除はできません。",
            )

        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}"),
                            "sk": _string_attr(f"MEMBER#{user_id}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"USER#{user_id}"),
                            "sk": _string_attr(f"GROUP#{group_id}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
            ]
        )

    def _cognito_subject(self, login_id: str) -> str:
        response = self._cognito.admin_get_user(
            UserPoolId=self._user_pool_id,
            Username=login_id,
        )
        attributes = response.get("UserAttributes")
        if not isinstance(attributes, list):
            raise RuntimeError("Cognito AdminGetUser response has no UserAttributes list")

        subjects: list[str] = []
        for attribute in attributes:
            if not isinstance(attribute, dict):
                raise RuntimeError("Cognito UserAttributes contains a non-object value")
            if attribute.get("Name") == "sub":
                value = attribute.get("Value")
                if not isinstance(value, str) or not value:
                    raise RuntimeError("Cognito sub attribute has an invalid value")
                subjects.append(value)

        if len(subjects) != 1:
            raise RuntimeError(f"Expected exactly one Cognito sub attribute, got {len(subjects)}")
        return subjects[0]

    def _user_by_auth_subject(self, auth_subject: str) -> _User:
        item = self._get_item(pk=f"AUTH#{auth_subject}", sk="PROFILE")
        if item is None:
            raise ApiProblem(
                403,
                "account_not_provisioned",
                "この認証アカウントはみんアプに登録されていません。",
            )
        return self._user_from_item(item)

    def _user_by_id(self, user_id: str) -> _User:
        item = self._get_item(pk=f"USER#{user_id}", sk="PROFILE")
        if item is None:
            raise ApiProblem(404, "user_not_found", "指定されたユーザーは存在しません。")
        return self._user_from_item(item)

    def _user_from_item(self, item: dict[str, Any]) -> _User:
        user = _User(
            user_id=_item_string(item, "user_id"),
            auth_subject=_item_string(item, "auth_subject"),
            login_id=_item_string(item, "login_id"),
            role=_item_string(item, "role"),
            status=_item_string(item, "status"),
        )
        if user.status != "active":
            raise ApiProblem(403, "account_inactive", "このアカウントは利用できません。")
        if user.role not in {"teacher", "student"}:
            raise RuntimeError(f"Unsupported stored user role: {user.role!r}")
        return user

    @staticmethod
    def _public_user(user: _User) -> dict[str, str]:
        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "status": user.status,
        }

    @staticmethod
    def _require_role(user: _User, required_role: str) -> None:
        if user.role != required_role:
            raise ApiProblem(403, "forbidden", "この操作を行う権限がありません。")

    def _require_teacher_membership(self, user_id: str, group_id: str) -> str:
        item = self._get_item(
            pk=f"GROUP#{group_id}",
            sk=f"MEMBER#{user_id}",
        )
        if item is None:
            raise ApiProblem(403, "forbidden", "このグループを管理する権限がありません。")
        if _item_string(item, "role") != "teacher" or _item_string(item, "status") != "active":
            raise ApiProblem(403, "forbidden", "このグループを管理する権限がありません。")
        return _item_string(item, "group_name")

    def _require_shared_teacher_group(self, teacher_user_id: str, student_user_id: str) -> None:
        teacher_memberships = self._membership_items_for_user(teacher_user_id)
        student_memberships = self._membership_items_for_user(student_user_id)

        teacher_group_ids = {
            _item_string(item, "group_id")
            for item in teacher_memberships
            if _item_string(item, "role") == "teacher"
            and _item_string(item, "status") == "active"
        }
        student_group_ids = {
            _item_string(item, "group_id")
            for item in student_memberships
            if _item_string(item, "role") == "student"
            and _item_string(item, "status") == "active"
        }
        if not teacher_group_ids.intersection(student_group_ids):
            raise ApiProblem(403, "forbidden", "この生徒を管理する権限がありません。")

    def _list_groups_for_user(self, user_id: str) -> list[dict[str, Any]]:
        memberships = self._membership_items_for_user(user_id)
        groups: list[dict[str, Any]] = []
        for membership in memberships:
            if _item_string(membership, "status") != "active":
                continue
            groups.append(
                {
                    "group_id": _item_string(membership, "group_id"),
                    "name": _item_string(membership, "group_name"),
                    "role": _item_string(membership, "role"),
                    "status": "active",
                }
            )
        groups.sort(key=lambda group: group["name"])
        return groups

    def _membership_items_for_user(self, user_id: str) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :group_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"USER#{user_id}"),
                ":group_prefix": _string_attr("GROUP#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    @staticmethod
    def _query_items(response: dict[str, Any]) -> list[dict[str, Any]]:
        items = response.get("Items")
        if not isinstance(items, list):
            raise RuntimeError("DynamoDB Query response has no Items list")
        for item in items:
            if not isinstance(item, dict):
                raise RuntimeError("DynamoDB Query returned a non-object item")
        last_key = response.get("LastEvaluatedKey")
        if last_key:
            raise RuntimeError(
                "DynamoDB query pagination is not implemented for Phase 1; "
                "refusing to return a partial result."
            )
        return items

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None:
        response = self._dynamodb.get_item(
            TableName=self._table_name,
            Key={"pk": _string_attr(pk), "sk": _string_attr(sk)},
            ConsistentRead=True,
        )
        item = response.get("Item")
        if item is None:
            return None
        if not isinstance(item, dict):
            raise RuntimeError("DynamoDB GetItem returned a non-object Item")
        return item

    def _transact_put_new(self, items: list[dict[str, Any]]) -> None:
        if not items:
            raise ValueError("At least one DynamoDB item is required")
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": item,
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                }
                for item in items
            ]
        )

    @staticmethod
    def _auth_item(user: _User) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"AUTH#{user.auth_subject}"),
            "sk": _string_attr("PROFILE"),
            "entity": _string_attr("auth_user"),
            "user_id": _string_attr(user.user_id),
            "auth_subject": _string_attr(user.auth_subject),
            "login_id": _string_attr(user.login_id),
            "role": _string_attr(user.role),
            "status": _string_attr(user.status),
        }

    @staticmethod
    def _user_item(user: _User) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"USER#{user.user_id}"),
            "sk": _string_attr("PROFILE"),
            "entity": _string_attr("user"),
            "user_id": _string_attr(user.user_id),
            "auth_subject": _string_attr(user.auth_subject),
            "login_id": _string_attr(user.login_id),
            "role": _string_attr(user.role),
            "status": _string_attr(user.status),
        }

    @staticmethod
    def _membership_item(
        *,
        pk: str,
        sk: str,
        user: _User,
        group_id: str,
        group_name: str,
        role: str,
    ) -> dict[str, Any]:
        return {
            "pk": _string_attr(pk),
            "sk": _string_attr(sk),
            "entity": _string_attr("membership"),
            "user_id": _string_attr(user.user_id),
            "login_id": _string_attr(user.login_id),
            "group_id": _string_attr(group_id),
            "group_name": _string_attr(group_name),
            "role": _string_attr(role),
            "status": _string_attr("active"),
        }
