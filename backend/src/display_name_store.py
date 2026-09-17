from __future__ import annotations

from typing import Any, Protocol

from aws_backend import _item_string, _string_attr
from phase2_backend import _optional_item_string

MAX_DISPLAY_NAME_LENGTH = 40


class _DisplayNameStoreBackend(Protocol):
    _dynamodb: Any
    _table_name: str

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None: ...


def read_display_name(backend: _DisplayNameStoreBackend, user_id: str) -> str | None:
    item = backend._get_item(pk=f"USER#{user_id}", sk="DISPLAY_NAME")
    if item is None:
        return None
    if _item_string(item, "entity") != "user_display_name":
        raise RuntimeError("Display-name item has an unexpected entity type")
    name = _optional_item_string(item, "display_name")
    if name is None:
        raise RuntimeError("Display-name item has no display_name")
    validate_display_name(name, stored=True)
    return name


def validate_display_name(display_name: str, *, stored: bool = False) -> str:
    if not isinstance(display_name, str):
        raise TypeError("display_name must be a string")
    if (
        display_name != display_name.strip()
        or len(display_name) < 1
        or len(display_name) > MAX_DISPLAY_NAME_LENGTH
    ):
        if stored:
            raise RuntimeError("Stored display_name is invalid")
        raise ValueError(
            f"display_name must be 1-{MAX_DISPLAY_NAME_LENGTH} characters without surrounding whitespace"
        )
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in display_name):
        if stored:
            raise RuntimeError("Stored display_name contains control characters")
        raise ValueError("display_name must not contain control characters")
    return display_name


def write_display_name(
    backend: _DisplayNameStoreBackend,
    user_id: str,
    display_name: str,
) -> None:
    value = validate_display_name(display_name)
    backend._dynamodb.put_item(
        TableName=backend._table_name,
        Item={
            "pk": _string_attr(f"USER#{user_id}"),
            "sk": _string_attr("DISPLAY_NAME"),
            "entity": _string_attr("user_display_name"),
            "user_id": _string_attr(user_id),
            "display_name": _string_attr(value),
        },
        ConditionExpression="attribute_not_exists(pk) OR user_id = :user_id",
        ExpressionAttributeValues={":user_id": _string_attr(user_id)},
    )
