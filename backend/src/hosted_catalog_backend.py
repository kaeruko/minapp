from __future__ import annotations

import json
import uuid
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_platform_backend import (
    HostedPlatformBackend,
    MAX_RUNTIME_VALUE_BYTES,
    _now_iso,
    _number_attr,
    _runtime_token_hash,
    _validate_state_key,
)

MAX_APPS_PER_GROUP = 20
MAX_RUNTIME_KEYS_PER_APP = 64
MAX_RUNTIME_BYTES_PER_APP = 256 * 1024
MAX_RUNTIME_REQUESTS_PER_SESSION = 300

BUILTIN_TEMPLATES: dict[str, dict[str, Any]] = {
    "shiba-game": {
        "builtin_id": "shiba-game",
        "version": 1,
        "title": "しば犬どんぐりキャッチ",
        "asset_path": "assets/builtin/shiba_donguri/index.html",
    },
    "shiba-goshujin": {
        "builtin_id": "shiba-goshujin",
        "version": 1,
        "title": "ごしゅじんどこわん",
        "asset_path": "assets/builtin/shiba_goshujin/index.html",
    },
}


def _optional_number(item: dict[str, Any], key: str) -> int | None:
    raw = item.get(key)
    if raw is None:
        return None
    if not isinstance(raw, dict) or not isinstance(raw.get("N"), str):
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a number")
    try:
        return int(raw["N"])
    except ValueError as exc:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not an integer") from exc


class HostedCatalogBackend(HostedPlatformBackend):
    """Hosted built-in installation/fork metadata plus MVP quotas."""

    def list_builtin_templates(self) -> list[dict[str, Any]]:
        return [dict(BUILTIN_TEMPLATES[key]) for key in sorted(BUILTIN_TEMPLATES)]

    def list_group_apps(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        apps = [self._public_hosted_app(item) for item in self._group_app_items(group_id)]
        apps.sort(key=lambda app: (app["title"], app["app_id"]))
        return apps

    def install_builtin(
        self,
        auth_subject: str,
        group_id: str,
        builtin_id: str,
    ) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        template = BUILTIN_TEMPLATES.get(builtin_id)
        if template is None:
            raise ApiProblem(404, "builtin_not_found", "指定されたビルトインアプリはありません。")
        self._require_app_capacity(group_id)

        for item in self._group_app_items(group_id):
            if item.get("builtin_id", {}).get("S") == builtin_id and item.get("source_kind", {}).get("S") == "builtin":
                raise ApiProblem(409, "builtin_already_installed", "このビルトインアプリはすでに入っています。")

        app_id = uuid.uuid4().hex
        created_at = _now_iso()
        common = {
            "entity": _string_attr("app"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "title": _string_attr(str(template["title"])),
            "owner_user_id": _string_attr(owner.user_id),
            "source_kind": _string_attr("builtin"),
            "builtin_id": _string_attr(builtin_id),
            "builtin_version": _number_attr(int(template["version"])),
            "builtin_asset_path": _string_attr(str(template["asset_path"])),
            "editable": {"BOOL": False},
            "created_at": _string_attr(created_at),
        }
        app_meta = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("META"),
            **common,
        }
        group_index = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{app_id}"),
            **common,
        }
        self._transact_put_new([app_meta, group_index])
        return self._public_hosted_app(app_meta)

    def fork_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        title: str,
    ) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        parent = self._require_app_in_group(app_id, group_id)
        self._require_app_capacity(group_id)

        new_app_id = uuid.uuid4().hex
        created_at = _now_iso()
        common: dict[str, Any] = {
            "entity": _string_attr("app"),
            "app_id": _string_attr(new_app_id),
            "group_id": _string_attr(group_id),
            "title": _string_attr(title),
            "owner_user_id": _string_attr(owner.user_id),
            "source_kind": _string_attr("fork"),
            "parent_app_id": _string_attr(app_id),
            "editable": {"BOOL": True},
            "created_at": _string_attr(created_at),
        }
        builtin_id = parent.get("builtin_id", {}).get("S")
        if isinstance(builtin_id, str) and builtin_id:
            common["builtin_id"] = _string_attr(builtin_id)
        builtin_version = _optional_number(parent, "builtin_version")
        if builtin_version is not None:
            common["builtin_version"] = _number_attr(builtin_version)
        asset_path = parent.get("builtin_asset_path", {}).get("S")
        if isinstance(asset_path, str) and asset_path:
            common["builtin_asset_path"] = _string_attr(asset_path)

        app_meta = {
            "pk": _string_attr(f"APP#{new_app_id}"),
            "sk": _string_attr("META"),
            **common,
        }
        group_index = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{new_app_id}"),
            **common,
        }
        self._transact_put_new([app_meta, group_index])
        return self._public_hosted_app(app_meta)

    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        self._require_app_in_group(app_id, group_id)

        runtime_items = self._runtime_items(group_id, app_id)
        if len(runtime_items) > MAX_RUNTIME_KEYS_PER_APP:
            raise RuntimeError("Runtime key count exceeds the configured deletion bound")
        if runtime_items:
            self._runtime_dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Delete": {
                            "TableName": self._runtime_table_name,
                            "Key": {"pk": item["pk"], "sk": item["sk"]},
                        }
                    }
                    for item in runtime_items
                ]
            )

        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"APP#{app_id}"),
                            "sk": _string_attr("META"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}"),
                            "sk": _string_attr(f"APP#{app_id}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
            ]
        )

    def get_runtime_state(self, token: str, key: str) -> dict[str, Any]:
        group_id, app_id, _ = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        item = self._runtime_get_item(group_id, app_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime state was not found.")
        raw_value = _item_string(item, "value_json")
        try:
            value = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Stored runtime JSON is invalid") from exc
        return {"key": key, "value": value, "updated_at": _item_string(item, "updated_at")}

    def set_runtime_state(self, token: str, key: str, value: Any) -> dict[str, Any]:
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

        items = self._runtime_items(group_id, app_id)
        existing = next((item for item in items if _item_string(item, "key") == key), None)
        if existing is None and len(items) >= MAX_RUNTIME_KEYS_PER_APP:
            raise ApiProblem(
                409,
                "runtime_key_limit_reached",
                f"1アプリが保存できるRuntimeキーは最大{MAX_RUNTIME_KEYS_PER_APP}個です。",
            )

        total_bytes = sum(self._runtime_item_bytes(item) for item in items)
        previous_bytes = 0 if existing is None else self._runtime_item_bytes(existing)
        if total_bytes - previous_bytes + value_bytes > MAX_RUNTIME_BYTES_PER_APP:
            raise ApiProblem(
                413,
                "runtime_storage_limit_reached",
                f"1アプリのRuntime保存容量は最大{MAX_RUNTIME_BYTES_PER_APP} bytesです。",
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
            "value_bytes": _number_attr(value_bytes),
            "updated_by": _string_attr(user_id),
            "updated_at": _string_attr(updated_at),
        }
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[{"Put": {"TableName": self._runtime_table_name, "Item": item}}]
        )
        return {"key": key, "value": value, "updated_at": updated_at}

    def delete_runtime_state(self, token: str, key: str) -> None:
        group_id, app_id, _ = self._consume_runtime_request(token)
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

    def _consume_runtime_request(self, token: str) -> tuple[str, str, str]:
        context = HostedPlatformBackend._runtime_context(self, token)
        token_hash = _runtime_token_hash(token)
        try:
            self._dynamodb.update_item(
                TableName=self._table_name,
                Key={
                    "pk": _string_attr(f"RUNTIMESESSION#{token_hash}"),
                    "sk": _string_attr("META"),
                },
                UpdateExpression="SET request_count = if_not_exists(request_count, :zero) + :one",
                ConditionExpression=(
                    "attribute_exists(pk) AND "
                    "(attribute_not_exists(request_count) OR request_count < :limit)"
                ),
                ExpressionAttributeValues={
                    ":zero": _number_attr(0),
                    ":one": _number_attr(1),
                    ":limit": _number_attr(MAX_RUNTIME_REQUESTS_PER_SESSION),
                },
            )
        except Exception as exc:
            if _aws_error_code(exc) == "ConditionalCheckFailedException":
                raise ApiProblem(
                    429,
                    "runtime_request_limit_reached",
                    "このRuntime sessionの操作上限に達しました。新しいsessionを開始してください。",
                ) from exc
            raise
        return context

    def _require_app_capacity(self, group_id: str) -> None:
        if len(self._group_app_items(group_id)) >= MAX_APPS_PER_GROUP:
            raise ApiProblem(
                409,
                "app_limit_reached",
                f"1グループに置けるアプリは最大{MAX_APPS_PER_GROUP}個です。",
            )

    def _runtime_items(self, group_id: str, app_id: str) -> list[dict[str, Any]]:
        response = self._runtime_dynamodb.query(
            TableName=self._runtime_table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :state_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                ":state_prefix": _string_attr("STATE#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    @staticmethod
    def _runtime_item_bytes(item: dict[str, Any]) -> int:
        stored = _optional_number(item, "value_bytes")
        if stored is not None:
            return stored
        return len(_item_string(item, "value_json").encode("utf-8"))

    @staticmethod
    def _public_hosted_app(item: dict[str, Any]) -> dict[str, Any]:
        result: dict[str, Any] = {
            "app_id": _item_string(item, "app_id"),
            "group_id": _item_string(item, "group_id"),
            "title": _item_string(item, "title"),
            "source_kind": _item_string(item, "source_kind"),
            "created_at": _item_string(item, "created_at"),
        }
        for field in ("builtin_id", "builtin_asset_path", "parent_app_id"):
            value = item.get(field, {}).get("S")
            if isinstance(value, str) and value:
                result[field] = value
        builtin_version = _optional_number(item, "builtin_version")
        if builtin_version is not None:
            result["builtin_version"] = builtin_version
        editable = item.get("editable", {}).get("BOOL")
        if isinstance(editable, bool):
            result["editable"] = editable
        return result
