from __future__ import annotations

import json
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import (
    MAX_RUNTIME_BYTES_PER_APP,
    MAX_RUNTIME_KEYS_PER_APP,
    MAX_RUNTIME_VALUE_BYTES,
    HostedCatalogBackend,
    _optional_number,
    _optional_string,
)
from hosted_platform_backend import (
    _now_iso,
    _number_attr,
    _runtime_token_hash,
    _validate_state_key,
)
from hosted_user_state_backend import (
    MAX_USER_STATE_BYTES_PER_USER_APP,
    MAX_USER_STATE_KEYS_PER_USER_APP,
    HostedUserStateBackend,
)


class HostedPreviewStateBackend(HostedUserStateBackend):
    """Ephemeral Runtime state for draft preview sessions.

    Preview state is stored in the Hosted metadata table under a random,
    server-issued preview scope with DynamoDB TTL. It never shares the
    persistent Runtime table keys used by published ``state`` or ``userState``.
    """

    def is_preview_runtime_session(self, token: str) -> bool:
        session = self._runtime_session_item(token)
        if session is None:
            return False
        preview_state_id = _optional_string(session, "preview_state_id")
        preview_state_ttl_epoch = _optional_number(
            session,
            "preview_state_ttl_epoch",
        )
        if preview_state_id is None and preview_state_ttl_epoch is None:
            return False
        self._validate_preview_scope(preview_state_id, preview_state_ttl_epoch)
        return True

    def get_preview_runtime_state(
        self,
        token: str,
        key: str,
        *,
        user_state: bool,
    ) -> dict[str, Any]:
        context = self._preview_context(token)
        key = _validate_state_key(key)
        sort_key = self._preview_sort_key(
            key=key,
            user_state=user_state,
            user_id=context[2],
        )
        item = self._preview_get_item(context[3], sort_key)
        if item is None:
            raise ApiProblem(
                404,
                "state_not_found",
                "Runtime preview state was not found.",
            )
        self._validate_stored_scope(
            item,
            group_id=context[0],
            app_id=context[1],
            user_id=context[2] if user_state else None,
        )
        raw_value = _item_string(item, "value_json")
        try:
            value = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Stored Runtime preview-state JSON is invalid") from exc
        return {
            "key": key,
            "value": value,
            "updated_at": _item_string(item, "updated_at"),
        }

    def set_preview_runtime_state(
        self,
        token: str,
        key: str,
        value: Any,
        *,
        user_state: bool,
    ) -> dict[str, Any]:
        context = self._preview_context(token)
        group_id, app_id, user_id, preview_state_id, ttl_epoch = context
        key = _validate_state_key(key)
        value_json = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        value_bytes = len(value_json.encode("utf-8"))
        if value_bytes > MAX_RUNTIME_VALUE_BYTES:
            raise ApiProblem(
                413,
                "runtime_value_too_large",
                f"Runtime state values must be at most {MAX_RUNTIME_VALUE_BYTES} bytes.",
            )

        prefix = self._preview_sort_prefix(
            user_state=user_state,
            user_id=user_id,
        )
        items = self._preview_items(preview_state_id, prefix)
        existing = next(
            (item for item in items if _item_string(item, "key") == key),
            None,
        )
        max_keys = (
            MAX_USER_STATE_KEYS_PER_USER_APP
            if user_state
            else MAX_RUNTIME_KEYS_PER_APP
        )
        max_bytes = (
            MAX_USER_STATE_BYTES_PER_USER_APP
            if user_state
            else MAX_RUNTIME_BYTES_PER_APP
        )
        if existing is None and len(items) >= max_keys:
            code = (
                "runtime_user_key_limit_reached"
                if user_state
                else "runtime_key_limit_reached"
            )
            raise ApiProblem(
                409,
                code,
                f"Preview Runtime state can store at most {max_keys} keys in this scope.",
            )

        total_bytes = sum(
            HostedCatalogBackend._runtime_item_bytes(item) for item in items
        )
        previous_bytes = (
            0
            if existing is None
            else HostedCatalogBackend._runtime_item_bytes(existing)
        )
        if total_bytes - previous_bytes + value_bytes > max_bytes:
            code = (
                "runtime_user_storage_limit_reached"
                if user_state
                else "runtime_storage_limit_reached"
            )
            raise ApiProblem(
                413,
                code,
                f"Preview Runtime state can store at most {max_bytes} bytes in this scope.",
            )

        updated_at = _now_iso()
        item: dict[str, Any] = {
            "pk": _string_attr(f"PREVIEWSTATE#{preview_state_id}"),
            "sk": _string_attr(
                self._preview_sort_key(
                    key=key,
                    user_state=user_state,
                    user_id=user_id,
                )
            ),
            "entity": _string_attr(
                "preview_runtime_user_state"
                if user_state
                else "preview_runtime_state"
            ),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "key": _string_attr(key),
            "value_json": _string_attr(value_json),
            "value_bytes": _number_attr(value_bytes),
            "updated_at": _string_attr(updated_at),
            "ttl_epoch": _number_attr(ttl_epoch),
        }
        if user_state:
            item["user_id"] = _string_attr(user_id)
        else:
            item["updated_by"] = _string_attr(user_id)
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table_name,
                        "Item": item,
                    }
                }
            ]
        )
        return {"key": key, "value": value, "updated_at": updated_at}

    def delete_preview_runtime_state(
        self,
        token: str,
        key: str,
        *,
        user_state: bool,
    ) -> None:
        context = self._preview_context(token)
        key = _validate_state_key(key)
        sort_key = self._preview_sort_key(
            key=key,
            user_state=user_state,
            user_id=context[2],
        )
        item = self._preview_get_item(context[3], sort_key)
        if item is None:
            raise ApiProblem(
                404,
                "state_not_found",
                "Runtime preview state was not found.",
            )
        self._validate_stored_scope(
            item,
            group_id=context[0],
            app_id=context[1],
            user_id=context[2] if user_state else None,
        )
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"PREVIEWSTATE#{context[3]}"),
                            "sk": _string_attr(sort_key),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
        )

    def _preview_context(self, token: str) -> tuple[str, str, str, str, int]:
        group_id, app_id, user_id = self._consume_runtime_request(token)
        session = self._runtime_session_item(token)
        if session is None:
            raise RuntimeError(
                "Runtime session disappeared after preview request validation"
            )
        preview_state_id = _optional_string(session, "preview_state_id")
        preview_state_ttl_epoch = _optional_number(
            session,
            "preview_state_ttl_epoch",
        )
        self._validate_preview_scope(preview_state_id, preview_state_ttl_epoch)
        return (
            group_id,
            app_id,
            user_id,
            preview_state_id,
            preview_state_ttl_epoch,
        )

    def _runtime_session_item(self, token: str) -> dict[str, Any] | None:
        token_hash = _runtime_token_hash(token)
        return self._get_item(
            pk=f"RUNTIMESESSION#{token_hash}",
            sk="META",
        )

    @staticmethod
    def _validate_preview_scope(
        preview_state_id: str | None,
        preview_state_ttl_epoch: int | None,
    ) -> None:
        if (
            preview_state_id is None
            or len(preview_state_id) != 64
            or any(character not in "0123456789abcdef" for character in preview_state_id)
        ):
            raise RuntimeError("Preview Runtime session has an invalid preview_state_id")
        if preview_state_ttl_epoch is None or preview_state_ttl_epoch <= 0:
            raise RuntimeError(
                "Preview Runtime session has an invalid preview_state_ttl_epoch"
            )

    def _preview_get_item(
        self,
        preview_state_id: str,
        sort_key: str,
    ) -> dict[str, Any] | None:
        response = self._dynamodb.get_item(
            TableName=self._table_name,
            Key={
                "pk": _string_attr(f"PREVIEWSTATE#{preview_state_id}"),
                "sk": _string_attr(sort_key),
            },
            ConsistentRead=True,
        )
        item = response.get("Item")
        if item is None:
            return None
        if not isinstance(item, dict):
            raise RuntimeError("DynamoDB GetItem returned a non-object Item")
        return item

    def _preview_items(
        self,
        preview_state_id: str,
        sort_prefix: str,
    ) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :state_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"PREVIEWSTATE#{preview_state_id}"),
                ":state_prefix": _string_attr(sort_prefix),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    @staticmethod
    def _preview_sort_prefix(*, user_state: bool, user_id: str) -> str:
        if user_state:
            return f"USER#{user_id}#STATE#"
        return "STATE#"

    @classmethod
    def _preview_sort_key(
        cls,
        *,
        key: str,
        user_state: bool,
        user_id: str,
    ) -> str:
        return cls._preview_sort_prefix(
            user_state=user_state,
            user_id=user_id,
        ) + key

    @staticmethod
    def _validate_stored_scope(
        item: dict[str, Any],
        *,
        group_id: str,
        app_id: str,
        user_id: str | None,
    ) -> None:
        if _item_string(item, "group_id") != group_id:
            raise RuntimeError("Preview state group_id does not match Runtime session")
        if _item_string(item, "app_id") != app_id:
            raise RuntimeError("Preview state app_id does not match Runtime session")
        if user_id is not None and _item_string(item, "user_id") != user_id:
            raise RuntimeError("Preview user state user_id does not match Runtime session")
