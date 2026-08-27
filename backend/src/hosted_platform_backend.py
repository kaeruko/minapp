from __future__ import annotations

import hashlib
import json
import re
import secrets
import time
from datetime import datetime, timezone
from typing import Any

from aws_backend import (
    _User,
    _aws_error_code,
    _item_string,
    _required_env,
    _string_attr,
)
from errors import ApiProblem
from hosted_backend import HostedAwsBackend

RECOVERY_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
RECOVERY_CODE_LENGTH = 20
RUNTIME_SESSION_TTL_SECONDS = 10 * 60
MAX_RUNTIME_VALUE_BYTES = 16 * 1024
_RECOVERY_CODE_RE = re.compile(r"^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{20}$")
_RUNTIME_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
_STATE_KEY_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")


def _number_attr(value: int) -> dict[str, str]:
    if not isinstance(value, int):
        raise TypeError("DynamoDB number must be an integer")
    return {"N": str(value)}


def _item_number(item: dict[str, Any], key: str) -> int:
    raw = item.get(key)
    if not isinstance(raw, dict):
        raise RuntimeError(f"DynamoDB item is missing number attribute {key!r}")
    value = raw.get("N")
    if not isinstance(value, str):
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a number")
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not an integer") from exc


def _optional_item_string(item: dict[str, Any], key: str) -> str | None:
    raw = item.get(key)
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise RuntimeError(f"DynamoDB item has invalid optional string attribute {key!r}")
    value = raw.get("S")
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"DynamoDB optional attribute {key!r} is not a non-empty string")
    return value


def _now_epoch() -> int:
    return int(time.time())


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _new_recovery_code() -> str:
    compact = "".join(secrets.choice(RECOVERY_CODE_ALPHABET) for _ in range(RECOVERY_CODE_LENGTH))
    return "-".join(compact[index : index + 4] for index in range(0, RECOVERY_CODE_LENGTH, 4))


def _normalize_recovery_code(code: str) -> str:
    if not isinstance(code, str):
        raise TypeError("recovery code must be a string")
    compact = code.strip().upper().replace("-", "")
    if _RECOVERY_CODE_RE.fullmatch(compact) is None:
        raise ApiProblem(401, "invalid_recovery_credentials", "IDまたはリカバリーコードが正しくありません。")
    return compact


def _recovery_hash(code: str) -> str:
    return hashlib.sha256(_normalize_recovery_code(code).encode("ascii")).hexdigest()


def _runtime_token_hash(token: str) -> str:
    if not isinstance(token, str) or _RUNTIME_TOKEN_RE.fullmatch(token) is None:
        raise ApiProblem(404, "runtime_session_not_found", "Runtime session is invalid or expired.")
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _validate_state_key(key: str) -> str:
    if not isinstance(key, str) or _STATE_KEY_RE.fullmatch(key) is None:
        raise ApiProblem(
            400,
            "invalid_state_key",
            "state key must start with a lowercase letter and contain only lowercase letters, digits, _, -, or .",
        )
    return key


class HostedPlatformBackend(HostedAwsBackend):
    """Hosted BtoC lifecycle plus scoped Runtime state.

    The runtime token is deliberately not a Cognito token. It is short-lived and
    scoped server-side to one user, group, and app. Runtime requests re-check
    both current membership and app/group association so removals take effect
    immediately.
    """

    def __init__(
        self,
        *,
        cognito: Any,
        dynamodb: Any,
        runtime_dynamodb: Any,
        user_pool_id: str,
        app_client_id: str,
        table_name: str,
        runtime_table_name: str,
    ) -> None:
        super().__init__(
            cognito=cognito,
            dynamodb=dynamodb,
            user_pool_id=user_pool_id,
            app_client_id=app_client_id,
            table_name=table_name,
        )
        self._runtime_dynamodb = runtime_dynamodb
        self._runtime_table_name = runtime_table_name

    @classmethod
    def from_environment(cls) -> "HostedPlatformBackend":
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required outside the AWS Lambda runtime. Install the development requirements explicitly."
            ) from exc

        dynamodb = boto3.client("dynamodb")
        return cls(
            cognito=boto3.client("cognito-idp"),
            dynamodb=dynamodb,
            runtime_dynamodb=dynamodb,
            user_pool_id=_required_env("USER_POOL_ID"),
            app_client_id=_required_env("USER_POOL_CLIENT_ID"),
            table_name=_required_env("DATA_TABLE_NAME"),
            runtime_table_name=_required_env("RUNTIME_TABLE_NAME"),
        )

    def register(self, login_id: str, password: str) -> dict[str, Any]:
        import uuid

        user_id = uuid.uuid4().hex
        recovery_code = _new_recovery_code()
        recovery_hash = _recovery_hash(recovery_code)

        try:
            self._cognito.admin_create_user(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                TemporaryPassword=password,
                MessageAction="SUPPRESS",
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code == "UsernameExistsException":
                raise ApiProblem(409, "login_id_conflict", "このIDはすでに使われています。") from exc
            if code == "InvalidPasswordException":
                raise ApiProblem(400, "invalid_password", "パスワードがポリシーを満たしていません。") from exc
            raise

        try:
            self._cognito.admin_set_user_password(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                Password=password,
                Permanent=True,
            )
            auth_subject = self._cognito_subject(login_id)
            user = _User(
                user_id=user_id,
                auth_subject=auth_subject,
                login_id=login_id,
                role="user",
                status="active",
            )
            auth_item = self._auth_item(user)
            user_item = self._user_item(user)
            auth_item["recovery_hash"] = _string_attr(recovery_hash)
            user_item["recovery_hash"] = _string_attr(recovery_hash)
            self._transact_put_new([auth_item, user_item])
        except Exception as original_exc:
            try:
                self._cognito.admin_delete_user(
                    UserPoolId=self._user_pool_id,
                    Username=login_id,
                )
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Hosted registration failed after Cognito user creation, and cleanup also failed."
                ) from cleanup_exc
            raise original_exc

        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "status": user.status,
            "recovery_code": recovery_code,
        }

    def recover_account(self, login_id: str, recovery_code: str, new_password: str) -> dict[str, Any]:
        try:
            auth_subject = self._cognito_subject(login_id)
        except Exception as exc:
            if _aws_error_code(exc) == "UserNotFoundException":
                raise ApiProblem(
                    401,
                    "invalid_recovery_credentials",
                    "IDまたはリカバリーコードが正しくありません。",
                ) from exc
            raise

        auth_item = self._get_item(pk=f"AUTH#{auth_subject}", sk="PROFILE")
        if auth_item is None:
            raise ApiProblem(
                401,
                "invalid_recovery_credentials",
                "IDまたはリカバリーコードが正しくありません。",
            )
        stored_hash = _optional_item_string(auth_item, "recovery_hash")
        supplied_hash = _recovery_hash(recovery_code)
        if stored_hash is None or not secrets.compare_digest(stored_hash, supplied_hash):
            raise ApiProblem(
                401,
                "invalid_recovery_credentials",
                "IDまたはリカバリーコードが正しくありません。",
            )

        user = self._user_from_item(auth_item)
        try:
            self._cognito.admin_set_user_password(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                Password=new_password,
                Permanent=True,
            )
        except Exception as exc:
            if _aws_error_code(exc) == "InvalidPasswordException":
                raise ApiProblem(400, "invalid_password", "パスワードがポリシーを満たしていません。") from exc
            raise

        new_recovery_code = self._rotate_recovery_hash(user)
        return {
            "login_id": login_id,
            "recovery_code": new_recovery_code,
        }

    def rotate_recovery_code(self, auth_subject: str) -> dict[str, str]:
        user = self._user_by_auth_subject(auth_subject)
        return {"recovery_code": self._rotate_recovery_hash(user)}

    def _rotate_recovery_hash(self, user: _User) -> str:
        recovery_code = _new_recovery_code()
        recovery_hash = _recovery_hash(recovery_code)
        auth_item = self._get_item(pk=f"AUTH#{user.auth_subject}", sk="PROFILE")
        user_item = self._get_item(pk=f"USER#{user.user_id}", sk="PROFILE")
        if auth_item is None or user_item is None:
            raise RuntimeError("Hosted user profile is incomplete")
        replacement_auth = dict(auth_item)
        replacement_user = dict(user_item)
        replacement_auth["recovery_hash"] = _string_attr(recovery_hash)
        replacement_user["recovery_hash"] = _string_attr(recovery_hash)
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": replacement_auth,
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": replacement_user,
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
            ]
        )
        return recovery_code

    def transfer_group_ownership(
        self, auth_subject: str, group_id: str, new_owner_user_id: str
    ) -> dict[str, str]:
        owner = self._user_by_auth_subject(auth_subject)
        group_item = self._require_owner_group(owner.user_id, group_id)
        if new_owner_user_id == owner.user_id:
            raise ApiProblem(409, "already_owner", "指定されたユーザーはすでにオーナーです。")

        target_group_membership = self._get_item(
            pk=f"GROUP#{group_id}", sk=f"MEMBER#{new_owner_user_id}"
        )
        target_user_membership = self._get_item(
            pk=f"USER#{new_owner_user_id}", sk=f"GROUP#{group_id}"
        )
        owner_group_membership = self._get_item(
            pk=f"GROUP#{group_id}", sk=f"MEMBER#{owner.user_id}"
        )
        owner_user_membership = self._get_item(
            pk=f"USER#{owner.user_id}", sk=f"GROUP#{group_id}"
        )
        if (
            target_group_membership is None
            or target_user_membership is None
            or _item_string(target_group_membership, "status") != "active"
            or _item_string(target_group_membership, "role") != "member"
        ):
            raise ApiProblem(404, "member_not_found", "新しいオーナーは有効なメンバーである必要があります。")
        if owner_group_membership is None or owner_user_membership is None:
            raise RuntimeError("Owner membership is incomplete")

        replacements: list[dict[str, Any]] = []
        for item, role in (
            (owner_group_membership, "member"),
            (owner_user_membership, "member"),
            (target_group_membership, "owner"),
            (target_user_membership, "owner"),
        ):
            replacement = dict(item)
            replacement["role"] = _string_attr(role)
            replacements.append(replacement)
        replacement_group = dict(group_item)
        replacement_group["owner_user_id"] = _string_attr(new_owner_user_id)
        replacements.append(replacement_group)

        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": item,
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
                for item in replacements
            ]
        )
        return {
            "group_id": group_id,
            "owner_user_id": new_owner_user_id,
        }

    def delete_group(self, auth_subject: str, group_id: str) -> None:
        owner = self._user_by_auth_subject(auth_subject)
        group_item = self._require_owner_group(owner.user_id, group_id)
        app_items = self._group_app_items(group_id)
        if app_items:
            raise ApiProblem(
                409,
                "group_has_apps",
                "アプリが残っているグループは削除できません。先にアプリを削除してください。",
            )

        members = self._membership_items_for_group(group_id)
        operations: list[dict[str, Any]] = [
            {
                "Delete": {
                    "TableName": self._table_name,
                    "Key": {
                        "pk": _string_attr(f"GROUP#{group_id}"),
                        "sk": _string_attr("META"),
                    },
                    "ConditionExpression": "attribute_exists(pk)",
                }
            }
        ]
        for member in members:
            user_id = _item_string(member, "user_id")
            operations.extend(
                [
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
        invite_hash = _optional_item_string(group_item, "invite_hash")
        if invite_hash is not None and self._get_item(pk=f"INVITE#{invite_hash}", sk="META") is not None:
            operations.append(
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"INVITE#{invite_hash}"),
                            "sk": _string_attr("META"),
                        },
                    }
                }
            )
        self._dynamodb.transact_write_items(TransactItems=operations)

    def _group_app_items(self, group_id: str) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :app_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}"),
                ":app_prefix": _string_attr("APP#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    def delete_account(self, auth_subject: str) -> None:
        user = self._user_by_auth_subject(auth_subject)
        memberships = self._membership_items_for_user(user.user_id)
        owned_groups = [
            _item_string(item, "group_id")
            for item in memberships
            if _item_string(item, "status") == "active" and _item_string(item, "role") == "owner"
        ]
        if owned_groups:
            raise ApiProblem(
                409,
                "owned_groups_exist",
                "所有しているグループを削除または他のメンバーへ移譲してから退会してください。",
            )

        auth_item = self._get_item(pk=f"AUTH#{user.auth_subject}", sk="PROFILE")
        user_item = self._get_item(pk=f"USER#{user.user_id}", sk="PROFILE")
        if auth_item is None or user_item is None:
            raise RuntimeError("Hosted user profile is incomplete")
        deleting_auth = dict(auth_item)
        deleting_user = dict(user_item)
        deleting_auth["status"] = _string_attr("deleting")
        deleting_user["status"] = _string_attr("deleting")

        operations: list[dict[str, Any]] = [
            {
                "Put": {
                    "TableName": self._table_name,
                    "Item": deleting_auth,
                    "ConditionExpression": "attribute_exists(pk)",
                }
            },
            {
                "Put": {
                    "TableName": self._table_name,
                    "Item": deleting_user,
                    "ConditionExpression": "attribute_exists(pk)",
                }
            },
        ]
        for membership in memberships:
            group_id = _item_string(membership, "group_id")
            operations.extend(
                [
                    {
                        "Delete": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"GROUP#{group_id}"),
                                "sk": _string_attr(f"MEMBER#{user.user_id}"),
                            },
                            "ConditionExpression": "attribute_exists(pk)",
                        }
                    },
                    {
                        "Delete": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"USER#{user.user_id}"),
                                "sk": _string_attr(f"GROUP#{group_id}"),
                            },
                            "ConditionExpression": "attribute_exists(pk)",
                        }
                    },
                ]
            )
        self._dynamodb.transact_write_items(TransactItems=operations)

        try:
            self._cognito.admin_delete_user(
                UserPoolId=self._user_pool_id,
                Username=user.login_id,
            )
        except Exception as exc:
            if _aws_error_code(exc) != "UserNotFoundException":
                raise

        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"AUTH#{user.auth_subject}"),
                            "sk": _string_attr("PROFILE"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"USER#{user.user_id}"),
                            "sk": _string_attr("PROFILE"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
            ]
        )

    def create_runtime_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        self._require_app_in_group(app_id, group_id)

        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        expires_at_epoch = _now_epoch() + RUNTIME_SESSION_TTL_SECONDS
        session_item = {
            "pk": _string_attr(f"RUNTIMESESSION#{token_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("runtime_session"),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "user_id": _string_attr(user.user_id),
            "expires_at_epoch": _number_attr(expires_at_epoch),
            "ttl_epoch": _number_attr(expires_at_epoch + 24 * 60 * 60),
        }
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": session_item,
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                }
            ]
        )
        return {
            "token": token,
            "expires_in": RUNTIME_SESSION_TTL_SECONDS,
        }

    def get_runtime_state(self, token: str, key: str) -> dict[str, Any]:
        group_id, app_id, _ = self._runtime_context(token)
        key = _validate_state_key(key)
        item = self._runtime_get_item(group_id, app_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime state was not found.")
        raw_value = _item_string(item, "value_json")
        try:
            value = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Stored runtime JSON is invalid") from exc
        return {
            "key": key,
            "value": value,
            "updated_at": _item_string(item, "updated_at"),
        }

    def set_runtime_state(self, token: str, key: str, value: Any) -> dict[str, Any]:
        group_id, app_id, user_id = self._runtime_context(token)
        key = _validate_state_key(key)
        value_json = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if len(value_json.encode("utf-8")) > MAX_RUNTIME_VALUE_BYTES:
            raise ApiProblem(
                413,
                "runtime_value_too_large",
                f"Runtime state values must be at most {MAX_RUNTIME_VALUE_BYTES} bytes.",
            )
        updated_at = _now_iso()
        item = {
            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
            "sk": _string_attr(f"STATE#{key}"),
            "entity": _string_attr("runtime_state"),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "key": _string_attr(key),
            "value_json": _string_attr(value_json),
            "updated_by": _string_attr(user_id),
            "updated_at": _string_attr(updated_at),
        }
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._runtime_table_name,
                        "Item": item,
                    }
                }
            ]
        )
        return {"key": key, "value": value, "updated_at": updated_at}

    def delete_runtime_state(self, token: str, key: str) -> None:
        group_id, app_id, _ = self._runtime_context(token)
        key = _validate_state_key(key)
        item = self._runtime_get_item(group_id, app_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime state was not found.")
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._runtime_table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                            "sk": _string_attr(f"STATE#{key}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
        )

    def _runtime_context(self, token: str) -> tuple[str, str, str]:
        token_hash = _runtime_token_hash(token)
        session = self._get_item(pk=f"RUNTIMESESSION#{token_hash}", sk="META")
        if session is None or _item_number(session, "expires_at_epoch") <= _now_epoch():
            raise ApiProblem(404, "runtime_session_not_found", "Runtime session is invalid or expired.")
        group_id = _item_string(session, "group_id")
        app_id = _item_string(session, "app_id")
        user_id = _item_string(session, "user_id")
        self._require_active_membership(user_id, group_id)
        self._require_app_in_group(app_id, group_id)
        return group_id, app_id, user_id

    def _require_app_in_group(self, app_id: str, group_id: str) -> dict[str, Any]:
        app = self._get_item(pk=f"APP#{app_id}", sk="META")
        if app is None or _item_string(app, "group_id") != group_id:
            raise ApiProblem(404, "app_not_found", "このグループのアプリが見つかりません。")
        return app

    def _runtime_get_item(self, group_id: str, app_id: str, key: str) -> dict[str, Any] | None:
        response = self._runtime_dynamodb.get_item(
            TableName=self._runtime_table_name,
            Key={
                "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                "sk": _string_attr(f"STATE#{key}"),
            },
            ConsistentRead=True,
        )
        item = response.get("Item")
        if item is None:
            return None
        if not isinstance(item, dict):
            raise RuntimeError("DynamoDB GetItem returned a non-object Item")
        return item
