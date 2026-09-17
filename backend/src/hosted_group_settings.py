from __future__ import annotations

from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem


def _put_existing(backend: Any, item: dict[str, Any]) -> dict[str, Any]:
    return {
        "Put": {
            "TableName": backend._table_name,
            "Item": item,
            "ConditionExpression": "attribute_exists(pk) AND attribute_exists(sk)",
        }
    }


def rename_group(
    backend: Any,
    auth_subject: str,
    group_id: str,
    name: str,
) -> dict[str, Any]:
    """Rename one hosted group and every denormalized membership copy atomically.

    Only the group owner may rename a group. The operation deliberately fails
    closed if any mirrored membership or current invite row is missing, rather
    than leaving different users with different group names.
    """

    if not isinstance(name, str) or not name or name != name.strip() or len(name) > 60:
        raise ApiProblem(
            400,
            "invalid_group_name",
            "グループ名は前後に空白を入れず、1〜60文字で入力してください。",
        )

    owner = backend._user_by_auth_subject(auth_subject)
    group_item = backend._require_owner_group(owner.user_id, group_id)
    current_name = _item_string(group_item, "name")

    if current_name == name:
        return _public_owner_group(group_item, name)

    members = backend._membership_items_for_group(group_id)
    if not members:
        raise RuntimeError("Hosted group has no membership rows")

    replacement_group = dict(group_item)
    replacement_group["name"] = _string_attr(name)
    operations: list[dict[str, Any]] = [_put_existing(backend, replacement_group)]

    invite_hash_raw = group_item.get("invite_hash")
    if invite_hash_raw is not None:
        invite_hash = _item_string(group_item, "invite_hash")
        invite_item = backend._get_item(pk=f"INVITE#{invite_hash}", sk="META")
        if invite_item is None:
            raise RuntimeError("Hosted group invite index is missing")
        replacement_invite = dict(invite_item)
        replacement_invite["group_name"] = _string_attr(name)
        operations.append(_put_existing(backend, replacement_invite))

    for group_membership in members:
        member_user_id = _item_string(group_membership, "user_id")
        user_membership = backend._get_item(
            pk=f"USER#{member_user_id}",
            sk=f"GROUP#{group_id}",
        )
        if user_membership is None:
            raise RuntimeError(
                f"Hosted user membership mirror is missing for {member_user_id}"
            )

        replacement_group_membership = dict(group_membership)
        replacement_group_membership["group_name"] = _string_attr(name)
        replacement_user_membership = dict(user_membership)
        replacement_user_membership["group_name"] = _string_attr(name)
        operations.extend(
            [
                _put_existing(backend, replacement_group_membership),
                _put_existing(backend, replacement_user_membership),
            ]
        )

    if len(operations) > 100:
        raise RuntimeError("Hosted group rename exceeded DynamoDB transaction capacity")

    backend._dynamodb.transact_write_items(TransactItems=operations)
    return _public_owner_group(replacement_group, name)


def _public_owner_group(group_item: dict[str, Any], name: str) -> dict[str, Any]:
    visibility = _item_string(group_item, "visibility")
    if visibility != "private":
        raise RuntimeError(f"Unsupported hosted group visibility: {visibility!r}")
    return {
        "group_id": _item_string(group_item, "group_id"),
        "name": name,
        "role": "owner",
        "status": "active",
        "visibility": visibility,
    }
