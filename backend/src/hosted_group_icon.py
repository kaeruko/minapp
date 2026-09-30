from __future__ import annotations

from typing import Any

from aws_backend import _string_attr
from errors import ApiProblem
from hosted_platform_backend import _now_iso
from hosted_thumbnail import _validate_thumbnail_bytes

_GROUP_ICON_FIELDS = (
    "group_icon_bytes",
    "group_icon_content_type",
    "group_icon_updated_at",
)


def _icon_from_group(group: dict[str, Any]) -> tuple[bytes, str]:
    raw = group.get("group_icon_bytes")
    if raw is None:
        raise ApiProblem(404, "group_icon_not_found", "グループアイコンは設定されていません。")
    if not isinstance(raw, dict):
        raise RuntimeError("DynamoDB group_icon_bytes is not an attribute object")
    stored = raw.get("B")
    if isinstance(stored, bytearray):
        data = bytes(stored)
    elif isinstance(stored, bytes):
        data = stored
    else:
        raise RuntimeError("DynamoDB group_icon_bytes is not binary")

    raw_content_type = group.get("group_icon_content_type")
    if (
        not isinstance(raw_content_type, dict)
        or not isinstance(raw_content_type.get("S"), str)
        or not raw_content_type["S"]
    ):
        raise RuntimeError("Stored group icon has no valid content type")
    content_type = raw_content_type["S"]
    _validate_thumbnail_bytes(data, content_type)
    return data, content_type


def get_group_icon(
    backend: Any,
    auth_subject: str,
    group_id: str,
) -> tuple[bytes, str]:
    user = backend._user_by_auth_subject(auth_subject)
    backend._require_active_membership(user.user_id, group_id)
    group = backend._get_item(pk=f"GROUP#{group_id}", sk="META")
    if group is None:
        raise RuntimeError(f"Membership points to missing group {group_id}")
    return _icon_from_group(group)


def set_group_icon(
    backend: Any,
    auth_subject: str,
    group_id: str,
    *,
    data: bytes,
    content_type: str,
) -> dict[str, Any]:
    _validate_thumbnail_bytes(data, content_type)
    owner = backend._user_by_auth_subject(auth_subject)
    backend._require_owner_group(owner.user_id, group_id)
    updated_at = _now_iso()

    backend._dynamodb.transact_write_items(
        TransactItems=[
            {
                "Update": {
                    "TableName": backend._table_name,
                    "Key": {
                        "pk": _string_attr(f"GROUP#{group_id}"),
                        "sk": _string_attr("META"),
                    },
                    "UpdateExpression": (
                        "SET group_icon_bytes = :icon_bytes, "
                        "group_icon_content_type = :content_type, "
                        "group_icon_updated_at = :updated_at"
                    ),
                    "ConditionExpression": "attribute_exists(pk) AND attribute_exists(sk)",
                    "ExpressionAttributeValues": {
                        ":icon_bytes": {"B": data},
                        ":content_type": _string_attr(content_type),
                        ":updated_at": _string_attr(updated_at),
                    },
                }
            }
        ]
    )
    return {
        "group_id": group_id,
        "content_type": content_type,
        "bytes": len(data),
        "updated_at": updated_at,
    }


def delete_group_icon(
    backend: Any,
    auth_subject: str,
    group_id: str,
) -> None:
    owner = backend._user_by_auth_subject(auth_subject)
    group = backend._require_owner_group(owner.user_id, group_id)
    replacement = dict(group)
    for field in _GROUP_ICON_FIELDS:
        replacement.pop(field, None)
    backend._dynamodb.transact_write_items(
        TransactItems=[
            {
                "Put": {
                    "TableName": backend._table_name,
                    "Item": replacement,
                    "ConditionExpression": "attribute_exists(pk)",
                }
            }
        ]
    )
