from __future__ import annotations

import hashlib
import secrets
import time
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import (
    MAX_RUNTIME_REQUESTS_PER_SESSION,
    _item_files,
    _optional_number,
)
from hosted_platform_backend import (
    RUNTIME_SESSION_TTL_SECONDS,
    _number_attr,
    _runtime_token_hash,
)
from hosted_shop_backend import (
    SHOP_CONTENT_SESSION_SECONDS,
    SHOP_CONTENT_TTL_GRACE_SECONDS,
    HostedShopBackend,
)


class HostedShopRuntimeBackend(HostedShopBackend):
    """Girls shop backend with Runtime state isolated from the source group."""

    @staticmethod
    def _shop_runtime_group_id(app_id: str) -> str:
        return hashlib.sha256(f"girls-shop:{app_id}".encode("ascii")).hexdigest()[:32]

    def create_shop_launch(
        self,
        auth_subject: str,
        app_id: str,
        version: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        app = self._current_shop_app(app_id)
        published_version = self._assert_version(app, version)
        files = _item_files(app, "published_files_json")
        if "index.html" not in files:
            raise RuntimeError("Listed hosted app has no index.html")

        content_token = secrets.token_urlsafe(32)
        content_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
        runtime_token = secrets.token_urlsafe(32)
        runtime_hash = _runtime_token_hash(runtime_token)
        now = int(time.time())
        content_expires_at = now + SHOP_CONTENT_SESSION_SECONDS
        runtime_expires_at = now + RUNTIME_SESSION_TTL_SECONDS
        ttl_grace = 24 * 60 * 60

        content_session = {
            "pk": _string_attr(f"SHOPCONTENT#{content_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("shop_content_session"),
            "issued_to_user_id": _string_attr(user.user_id),
            "app_id": _string_attr(app_id),
            "published_version": _number_attr(published_version),
            "published_key": _string_attr(_item_string(app, "published_key")),
            "published_sha256": _string_attr(_item_string(app, "published_sha256")),
            "published_files_json": _string_attr(_item_string(app, "published_files_json")),
            "expires_at_epoch": _number_attr(content_expires_at),
            "ttl_epoch": _number_attr(content_expires_at + SHOP_CONTENT_TTL_GRACE_SECONDS),
        }
        runtime_session = {
            "pk": _string_attr(f"RUNTIMESESSION#{runtime_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("shop_runtime_session"),
            "group_id": _string_attr(self._shop_runtime_group_id(app_id)),
            "app_id": _string_attr(app_id),
            "user_id": _string_attr(user.user_id),
            "published_version": _number_attr(published_version),
            "expires_at_epoch": _number_attr(runtime_expires_at),
            "ttl_epoch": _number_attr(runtime_expires_at + ttl_grace),
        }
        self._transact_put_new([content_session, runtime_session])
        return {
            "content_path": f"/shop/content/{content_token}/index.html",
            "runtime_token": runtime_token,
            "expires_in": min(SHOP_CONTENT_SESSION_SECONDS, RUNTIME_SESSION_TTL_SECONDS),
        }

    def _consume_runtime_request(self, token: str) -> tuple[str, str, str]:
        token_hash = _runtime_token_hash(token)
        session = self._get_item(pk=f"RUNTIMESESSION#{token_hash}", sk="META")
        if session is None:
            return super()._consume_runtime_request(token)

        entity = _item_string(session, "entity")
        if entity != "shop_runtime_session":
            return super()._consume_runtime_request(token)
        expires_at = _optional_number(session, "expires_at_epoch")
        if expires_at is None or expires_at <= int(time.time()):
            raise ApiProblem(404, "runtime_session_not_found", "Runtime session is invalid or expired.")

        app_id = _item_string(session, "app_id")
        self._current_shop_app(app_id)
        group_id = _item_string(session, "group_id")
        expected_group_id = self._shop_runtime_group_id(app_id)
        if group_id != expected_group_id:
            raise RuntimeError("Shop Runtime namespace does not match app_id")
        user_id = _item_string(session, "user_id")

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
        return group_id, app_id, user_id
