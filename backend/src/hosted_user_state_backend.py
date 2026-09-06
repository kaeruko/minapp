from __future__ import annotations

import json
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import HostedCatalogBackend, MAX_RUNTIME_VALUE_BYTES
from hosted_legal_backend import HostedLegalBackend
from hosted_platform_backend import _now_iso, _number_attr, _validate_state_key

MAX_USER_STATE_KEYS_PER_USER_APP = 64
MAX_USER_STATE_BYTES_PER_USER_APP = 256 * 1024


class HostedUserStateBackend(HostedLegalBackend):
    """Hosted backend with private per-user Runtime state.

    Shared ``minapp.state`` remains on ``STATE#{key}``. Private state uses a
    separate sort-key namespace derived only from the authenticated Runtime
    session's server-side user_id. Child code never supplies user_id.
    """

    def get_runtime_user_state(self, token: str, key: str) -> dict[str, Any]:
        group_id, app_id, user_id = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        item = self._runtime_user_get_item(group_id, app_id, user_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime user state was not found.")
        raw_value = _item_string(item, "value_json")
        try:
            value = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Stored Runtime user-state JSON is invalid") from exc
        return {
            "key": key,
            "value": value,
            "updated_at": _item_string(item, "updated_at"),
        }

    def set_runtime_user_state(
        self, token: str, key: str, value: Any
    ) -> dict[str, Any]:
        group_id, app_id, user_id = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        value_json = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        value_bytes = len(value_json.encode("utf-8"))
        if value_bytes > MAX_RUNTIME_VALUE_BYTES:
            raise ApiProblem(
                413,
                "runtime_value_too_large",
                f"Runtime state values must be at most {MAX_RUNTIME_VALUE_BYTES} bytes.",
            )

        items = self._runtime_user_items(group_id, app_id, user_id)
        existing = next((item for item in items if _item_string(item, "key") == key), None)
        if existing is None and len(items) >= MAX_USER_STATE_KEYS_PER_USER_APP:
            raise ApiProblem(
                409,
                "runtime_user_key_limit_reached",
                f"1ユーザー・1アプリが保存できるUser Dataキーは最大{MAX_USER_STATE_KEYS_PER_USER_APP}個です。",
            )

        total_bytes = sum(HostedCatalogBackend._runtime_item_bytes(item) for item in items)
        previous_bytes = (
            0 if existing is None else HostedCatalogBackend._runtime_item_bytes(existing)
        )
        if total_bytes - previous_bytes + value_bytes > MAX_USER_STATE_BYTES_PER_USER_APP:
            raise ApiProblem(
                413,
                "runtime_user_storage_limit_reached",
                f"1ユーザー・1アプリのUser Data保存容量は最大{MAX_USER_STATE_BYTES_PER_USER_APP} bytesです。",
            )

        updated_at = _now_iso()
        item = {
            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
            "sk": _string_attr(f"USER#{user_id}#STATE#{key}"),
            "entity": _string_attr("runtime_user_state"),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "user_id": _string_attr(user_id),
            "key": _string_attr(key),
            "value_json": _string_attr(value_json),
            "value_bytes": _number_attr(value_bytes),
            "updated_at": _string_attr(updated_at),
        }
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[{"Put": {"TableName": self._runtime_table_name, "Item": item}}]
        )
        return {"key": key, "value": value, "updated_at": updated_at}

    def delete_runtime_user_state(self, token: str, key: str) -> None:
        group_id, app_id, user_id = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        item = self._runtime_user_get_item(group_id, app_id, user_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime user state was not found.")
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._runtime_table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                            "sk": _string_attr(f"USER#{user_id}#STATE#{key}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
        )

    def _runtime_user_get_item(
        self, group_id: str, app_id: str, user_id: str, key: str
    ) -> dict[str, Any] | None:
        response = self._runtime_dynamodb.get_item(
            TableName=self._runtime_table_name,
            Key={
                "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                "sk": _string_attr(f"USER#{user_id}#STATE#{key}"),
            },
            ConsistentRead=True,
        )
        item = response.get("Item")
        if item is None:
            return None
        if not isinstance(item, dict):
            raise RuntimeError("DynamoDB GetItem returned a non-object Item")
        return item

    def _runtime_user_items(
        self, group_id: str, app_id: str, user_id: str
    ) -> list[dict[str, Any]]:
        response = self._runtime_dynamodb.query(
            TableName=self._runtime_table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :state_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                ":state_prefix": _string_attr(f"USER#{user_id}#STATE#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)
