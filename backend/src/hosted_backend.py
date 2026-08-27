from __future__ import annotations

import hashlib
import re
import secrets
import time
import uuid
from datetime import datetime, timezone
from typing import Any

from aws_backend import (
    AwsBackend,
    _User,
    _aws_error_code,
    _item_string,
    _string_attr,
)
from errors import ApiProblem

MAX_GROUPS_PER_USER = 20
MAX_MEMBERS_PER_GROUP = 20
INVITE_TTL_SECONDS = 7 * 24 * 60 * 60
_INVITE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
_INVITE_CODE_RE = re.compile(r"^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}$")


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


def _iso_from_epoch(value: int) -> str:
    return datetime.fromtimestamp(value, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _new_invite_code() -> str:
    compact = "".join(secrets.choice(_INVITE_ALPHABET) for _ in range(12))
    return f"{compact[:4]}-{compact[4:8]}-{compact[8:]}"


def _normalize_invite_code(code: str) -> str:
    if not isinstance(code, str):
        raise TypeError("invite code must be a string")
    compact = code.strip().upper().replace("-", "")
    if _INVITE_CODE_RE.fullmatch(compact) is None:
        raise ApiProblem(400, "invalid_invite_code", "招待コードの形式が正しくありません。")
    return compact


def _invite_hash(code: str) -> str:
    return hashlib.sha256(_normalize_invite_code(code).encode("ascii")).hexdigest()


class HostedAwsBackend(AwsBackend):
    """BtoC/shared-tenant identity and group operations.

    Global users have role ``user``. Human sharing permissions live in Membership
    rows with role ``owner`` or ``member``. This is deliberately separate from
    the dedicated-school ``teacher``/``student`` model.
    """

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
        if user.role != "user":
            raise RuntimeError(f"Unsupported hosted user role: {user.role!r}")
        return user

    def register(self, login_id: str, password: str) -> dict[str, Any]:
        user_id = uuid.uuid4().hex

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
            self._transact_put_new([self._auth_item(user), self._user_item(user)])
        except Exception as original_exc:
            try:
                self._cognito.admin_delete_user(
                    UserPoolId=self._user_pool_id,
                    Username=login_id,
                )
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Hosted registration failed after Cognito user creation, "
                    "and cleanup of the Cognito user also failed."
                ) from cleanup_exc
            raise original_exc

        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "status": user.status,
        }

    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_role(owner, "user")

        memberships = self._membership_items_for_user(owner.user_id)
        if len(memberships) >= MAX_GROUPS_PER_USER:
            raise ApiProblem(
                409,
                "group_limit_reached",
                f"1アカウントが参加できるグループは最大{MAX_GROUPS_PER_USER}個です。",
            )

        group_id = uuid.uuid4().hex
        group_item = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("group"),
            "group_id": _string_attr(group_id),
            "name": _string_attr(name),
            "created_by": _string_attr(owner.user_id),
            "visibility": _string_attr("private"),
        }
        group_member_item = self._membership_item(
            pk=f"GROUP#{group_id}",
            sk=f"MEMBER#{owner.user_id}",
            user=owner,
            group_id=group_id,
            group_name=name,
            role="owner",
        )
        user_membership_item = self._membership_item(
            pk=f"USER#{owner.user_id}",
            sk=f"GROUP#{group_id}",
            user=owner,
            group_id=group_id,
            group_name=name,
            role="owner",
        )
        self._transact_put_new([group_item, group_member_item, user_membership_item])

        return {
            "group_id": group_id,
            "name": name,
            "role": "owner",
            "status": "active",
            "visibility": "private",
        }

    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, str]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        members = []
        for item in self._membership_items_for_group(group_id):
            if _item_string(item, "status") != "active":
                continue
            members.append(
                {
                    "user_id": _item_string(item, "user_id"),
                    "login_id": _item_string(item, "login_id"),
                    "role": _item_string(item, "role"),
                    "status": "active",
                }
            )
        members.sort(key=lambda member: (member["role"], member["login_id"]))
        return members

    def create_invite(self, auth_subject: str, group_id: str) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        group_item = self._require_owner_group(owner.user_id, group_id)
        group_name = _item_string(group_item, "name")

        code = _new_invite_code()
        code_hash = _invite_hash(code)
        expires_at_epoch = _now_epoch() + INVITE_TTL_SECONDS

        invite_item = {
            "pk": _string_attr(f"INVITE#{code_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("group_invite"),
            "code_hash": _string_attr(code_hash),
            "group_id": _string_attr(group_id),
            "group_name": _string_attr(group_name),
            "created_by": _string_attr(owner.user_id),
            "status": _string_attr("active"),
            "expires_at_epoch": _number_attr(expires_at_epoch),
        }

        replacement_group = dict(group_item)
        replacement_group["invite_hash"] = _string_attr(code_hash)
        replacement_group["invite_status"] = _string_attr("active")
        replacement_group["invite_expires_at_epoch"] = _number_attr(expires_at_epoch)

        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": invite_item,
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": replacement_group,
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
            ]
        )

        return {
            "group_id": group_id,
            "code": code,
            "expires_at": _iso_from_epoch(expires_at_epoch),
            "valid_for_seconds": INVITE_TTL_SECONDS,
        }

    def revoke_invite(self, auth_subject: str, group_id: str) -> None:
        owner = self._user_by_auth_subject(auth_subject)
        group_item = self._require_owner_group(owner.user_id, group_id)
        if _optional_item_string(group_item, "invite_hash") is None or _optional_item_string(
            group_item, "invite_status"
        ) != "active":
            raise ApiProblem(404, "active_invite_not_found", "有効な招待コードはありません。")

        replacement_group = dict(group_item)
        replacement_group["invite_status"] = _string_attr("revoked")
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": replacement_group,
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
        )

    def join_group(self, auth_subject: str, invite_code: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_role(user, "user")

        normalized = _normalize_invite_code(invite_code)
        code_hash = hashlib.sha256(normalized.encode("ascii")).hexdigest()
        invite_item = self._get_item(pk=f"INVITE#{code_hash}", sk="META")
        if invite_item is None:
            raise ApiProblem(404, "invite_not_found", "招待コードが見つからないか、無効です。")

        expires_at_epoch = _item_number(invite_item, "expires_at_epoch")
        if expires_at_epoch <= _now_epoch():
            raise ApiProblem(410, "invite_expired", "この招待コードの有効期限は切れています。")

        group_id = _item_string(invite_item, "group_id")
        group_item = self._get_item(pk=f"GROUP#{group_id}", sk="META")
        if group_item is None:
            raise RuntimeError(f"Invite points to missing group {group_id}")
        if (
            _optional_item_string(group_item, "invite_hash") != code_hash
            or _optional_item_string(group_item, "invite_status") != "active"
        ):
            raise ApiProblem(404, "invite_not_found", "招待コードが見つからないか、無効です。")
        if _item_number(group_item, "invite_expires_at_epoch") <= _now_epoch():
            raise ApiProblem(410, "invite_expired", "この招待コードの有効期限は切れています。")

        if self._get_item(pk=f"USER#{user.user_id}", sk=f"GROUP#{group_id}") is not None:
            raise ApiProblem(409, "already_member", "すでにこのグループに参加しています。")

        user_memberships = self._membership_items_for_user(user.user_id)
        if len(user_memberships) >= MAX_GROUPS_PER_USER:
            raise ApiProblem(
                409,
                "group_limit_reached",
                f"1アカウントが参加できるグループは最大{MAX_GROUPS_PER_USER}個です。",
            )

        group_memberships = self._membership_items_for_group(group_id)
        active_members = [
            item for item in group_memberships if _item_string(item, "status") == "active"
        ]
        if len(active_members) >= MAX_MEMBERS_PER_GROUP:
            raise ApiProblem(
                409,
                "group_full",
                f"1グループに参加できる人数は最大{MAX_MEMBERS_PER_GROUP}人です。",
            )

        group_name = _item_string(group_item, "name")
        self._transact_put_new(
            [
                self._membership_item(
                    pk=f"USER#{user.user_id}",
                    sk=f"GROUP#{group_id}",
                    user=user,
                    group_id=group_id,
                    group_name=group_name,
                    role="member",
                ),
                self._membership_item(
                    pk=f"GROUP#{group_id}",
                    sk=f"MEMBER#{user.user_id}",
                    user=user,
                    group_id=group_id,
                    group_name=group_name,
                    role="member",
                ),
            ]
        )
        return {
            "group_id": group_id,
            "name": group_name,
            "role": "member",
            "status": "active",
        }

    def leave_group(self, auth_subject: str, group_id: str) -> None:
        user = self._user_by_auth_subject(auth_subject)
        membership = self._require_active_membership(user.user_id, group_id)
        role = _item_string(membership, "role")
        if role == "owner":
            raise ApiProblem(
                409,
                "owner_cannot_leave",
                "オーナーはグループをそのまま退出できません。",
            )
        if role != "member":
            raise RuntimeError(f"Unsupported hosted membership role: {role!r}")
        self._delete_membership(user.user_id, group_id)

    def remove_member(self, auth_subject: str, group_id: str, user_id: str) -> None:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        target = self._get_item(pk=f"GROUP#{group_id}", sk=f"MEMBER#{user_id}")
        if target is None or _item_string(target, "status") != "active":
            raise ApiProblem(404, "member_not_found", "指定されたメンバーは存在しません。")
        if _item_string(target, "role") == "owner":
            raise ApiProblem(409, "owner_removal_not_supported", "オーナーは削除できません。")
        if _item_string(target, "role") != "member":
            raise RuntimeError("Unsupported hosted membership role")
        self._delete_membership(user_id, group_id)

    def _delete_membership(self, user_id: str, group_id: str) -> None:
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

    def _require_active_membership(self, user_id: str, group_id: str) -> dict[str, Any]:
        item = self._get_item(pk=f"GROUP#{group_id}", sk=f"MEMBER#{user_id}")
        if item is None or _item_string(item, "status") != "active":
            raise ApiProblem(403, "forbidden", "このグループのメンバーではありません。")
        role = _item_string(item, "role")
        if role not in {"owner", "member"}:
            raise RuntimeError(f"Unsupported hosted membership role: {role!r}")
        return item

    def _require_owner_group(self, user_id: str, group_id: str) -> dict[str, Any]:
        membership = self._require_active_membership(user_id, group_id)
        if _item_string(membership, "role") != "owner":
            raise ApiProblem(403, "forbidden", "このグループを管理する権限がありません。")
        group_item = self._get_item(pk=f"GROUP#{group_id}", sk="META")
        if group_item is None:
            raise RuntimeError(f"Membership points to missing group {group_id}")
        return group_item

    def _membership_items_for_group(self, group_id: str) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :member_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}"),
                ":member_prefix": _string_attr("MEMBER#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)
