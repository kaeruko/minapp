from __future__ import annotations

import hashlib
import io
import secrets
import time
import zipfile
from datetime import datetime, timezone
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import (
    _content_type,
    _files_json,
    _item_files,
    _optional_number,
    _optional_string,
)
from hosted_platform_backend import _now_iso, _number_attr

PREVIEW_SESSION_SECONDS = 10 * 60
PREVIEW_TTL_GRACE_SECONDS = 24 * 60 * 60


def _visibility(item: dict[str, Any]) -> str:
    value = _optional_string(item, "visibility_state")
    if value is None:
        return "visible"
    if value != "hidden":
        raise RuntimeError(f"Unsupported app visibility state: {value!r}")
    return value


def _owned_editable_app(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> tuple[Any, dict[str, Any]]:
    user = backend._user_by_auth_subject(auth_subject)
    app = backend._get_item(pk=f"APP#{app_id}", sk="META")
    if app is None:
        raise ApiProblem(404, "app_not_found", "指定されたアプリはありません。")
    if app.get("editable", {}).get("BOOL") is not True:
        raise ApiProblem(409, "app_not_manageable", "このアプリはマイアプリから管理できません。")
    if _item_string(app, "owner_user_id") != user.user_id:
        raise ApiProblem(403, "forbidden", "このアプリを管理する権限がありません。")
    group_id = _item_string(app, "group_id")
    backend._require_owner_group(user.user_id, group_id)
    if _optional_string(app, "deletion_state") is not None:
        raise ApiProblem(409, "app_deleting", "このアプリは削除処理中です。")
    return user, app


def _stats(backend: Any, app_id: str) -> dict[str, int]:
    stats_pk = f"APPSTATS#{app_id}"
    total_item = backend._get_item(pk=stats_pk, sk="TOTAL")
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    month_item = backend._get_item(pk=stats_pk, sk=f"MONTH#{month}")

    response = backend._dynamodb.query(
        TableName=backend._table_name,
        KeyConditionExpression="pk = :pk AND begins_with(sk, :user_prefix)",
        ExpressionAttributeValues={
            ":pk": _string_attr(stats_pk),
            ":user_prefix": _string_attr("USER#"),
        },
        ConsistentRead=True,
    )
    users = backend._query_items(response)
    return {
        "total_plays": 0 if total_item is None else (_optional_number(total_item, "play_count") or 0),
        "unique_users": len(users),
        "monthly_plays": 0 if month_item is None else (_optional_number(month_item, "play_count") or 0),
    }


def _managed_payload(backend: Any, item: dict[str, Any]) -> dict[str, Any]:
    payload = backend._public_hosted_app(item)
    payload["visibility"] = _visibility(item)
    payload["stats"] = _stats(backend, _item_string(item, "app_id"))
    return payload


def list_managed_apps(backend: Any, auth_subject: str) -> list[dict[str, Any]]:
    user = backend._user_by_auth_subject(auth_subject)
    result: list[dict[str, Any]] = []
    for group in backend.list_groups(auth_subject):
        if group.get("role") != "owner" or group.get("status") != "active":
            continue
        group_id = group.get("group_id")
        if not isinstance(group_id, str):
            raise RuntimeError("Hosted group response has no group_id")
        for item in backend._group_app_items(group_id):
            if item.get("editable", {}).get("BOOL") is not True:
                continue
            if _item_string(item, "owner_user_id") != user.user_id:
                continue
            if _optional_string(item, "deletion_state") is not None:
                continue
            payload = _managed_payload(backend, item)
            payload["group_name"] = group.get("name")
            result.append(payload)
    result.sort(key=lambda app: (app["title"], app["app_id"]))
    return result


def _source_history(backend: Any, app_id: str) -> list[dict[str, Any]]:
    rows = []
    for item in backend._source_manifests(app_id):
        rows.append(
            {
                "revision": _optional_number(item, "source_revision"),
                "created_at": _item_string(item, "created_at"),
                "sha256": _item_string(item, "source_sha256"),
            }
        )
    rows.sort(key=lambda row: row["revision"] or 0, reverse=True)
    return rows


def _published_history(backend: Any, app_id: str) -> list[dict[str, Any]]:
    rows = []
    for item in backend._published_manifests(app_id):
        rows.append(
            {
                "version": _optional_number(item, "published_version"),
                "source_revision": _optional_number(item, "source_revision"),
                "published_at": _item_string(item, "published_at"),
                "sha256": _item_string(item, "published_sha256"),
            }
        )
    rows.sort(key=lambda row: row["version"] or 0, reverse=True)
    return rows


def get_managed_app(backend: Any, auth_subject: str, app_id: str) -> dict[str, Any]:
    _, app = _owned_editable_app(backend, auth_subject, app_id)
    payload = _managed_payload(backend, app)
    payload["source_history"] = _source_history(backend, app_id)
    payload["published_history"] = _published_history(backend, app_id)
    return payload


def set_visibility(
    backend: Any,
    auth_subject: str,
    app_id: str,
    *,
    hidden: bool,
) -> dict[str, Any]:
    _, app = _owned_editable_app(backend, auth_subject, app_id)
    group_id = _item_string(app, "group_id")
    updated_at = _now_iso()

    if hidden:
        update_expression = "SET visibility_state = :hidden, visibility_updated_at = :updated_at"
        values = {
            ":hidden": _string_attr("hidden"),
            ":updated_at": _string_attr(updated_at),
        }
    else:
        update_expression = "SET visibility_updated_at = :updated_at REMOVE visibility_state"
        values = {":updated_at": _string_attr(updated_at)}

    backend._dynamodb.transact_write_items(
        TransactItems=[
            {
                "Update": {
                    "TableName": backend._table_name,
                    "Key": {
                        "pk": _string_attr(f"APP#{app_id}"),
                        "sk": _string_attr("META"),
                    },
                    "UpdateExpression": update_expression,
                    "ConditionExpression": "attribute_exists(pk) AND attribute_not_exists(deletion_state)",
                    "ExpressionAttributeValues": values,
                }
            },
            {
                "Update": {
                    "TableName": backend._table_name,
                    "Key": {
                        "pk": _string_attr(f"GROUP#{group_id}"),
                        "sk": _string_attr(f"APP#{app_id}"),
                    },
                    "UpdateExpression": update_expression,
                    "ConditionExpression": "attribute_exists(pk) AND attribute_not_exists(deletion_state)",
                    "ExpressionAttributeValues": values,
                }
            },
        ]
    )
    refreshed = backend._get_item(pk=f"APP#{app_id}", sk="META")
    if refreshed is None:
        raise RuntimeError("Managed app disappeared after visibility update")
    return _managed_payload(backend, refreshed)


def create_preview_session(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> dict[str, Any]:
    user, app = _owned_editable_app(backend, auth_subject, app_id)
    group_id = _item_string(app, "group_id")
    source_revision = backend._source_revision(app)

    # Validate the immutable draft object before issuing a capability for it.
    _, files, sha256 = backend._read_current_source(app)
    source_key = _item_string(app, "source_key")

    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
    expires_at_epoch = int(time.time()) + PREVIEW_SESSION_SECONDS
    session = {
        "pk": _string_attr(f"HOSTEDPREVIEW#{token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("hosted_preview_session"),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(app_id),
        "source_revision": _number_attr(source_revision),
        "source_key": _string_attr(source_key),
        "source_sha256": _string_attr(sha256),
        "source_files_json": _string_attr(_files_json(files)),
        "expires_at_epoch": _number_attr(expires_at_epoch),
        "ttl_epoch": _number_attr(expires_at_epoch + PREVIEW_TTL_GRACE_SECONDS),
    }
    backend._transact_put_new([session])
    return {
        "app_id": app_id,
        "group_id": group_id,
        "source_revision": source_revision,
        "content_path": f"/hosted/preview/{token}/index.html",
        "expires_in": PREVIEW_SESSION_SECONDS,
    }


def get_preview_file(
    backend: Any,
    token: str,
    path: str,
) -> tuple[bytes, str]:
    if not isinstance(token, str) or not token or len(token) > 128:
        raise ApiProblem(404, "preview_content_not_found", "Preview content was not found.")
    token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
    session = backend._get_item(pk=f"HOSTEDPREVIEW#{token_hash}", sk="META")
    if session is None or (_optional_number(session, "expires_at_epoch") or 0) <= int(time.time()):
        raise ApiProblem(404, "preview_content_not_found", "Preview content was not found.")

    user_id = _item_string(session, "user_id")
    group_id = _item_string(session, "group_id")
    app_id = _item_string(session, "app_id")
    backend._require_owner_group(user_id, group_id)
    app = backend._require_app_in_group(app_id, group_id)
    if app.get("editable", {}).get("BOOL") is not True:
        raise ApiProblem(409, "app_not_manageable", "このアプリはプレビューできません。")
    if _item_string(app, "owner_user_id") != user_id:
        raise ApiProblem(403, "forbidden", "このアプリをプレビューする権限がありません。")
    if _optional_string(app, "deletion_state") is not None:
        raise ApiProblem(409, "app_deleting", "このアプリは削除処理中です。")

    normalized = backend._normalize_content_path(path)
    expected_files = _item_files(session, "source_files_json")
    if normalized not in expected_files:
        raise ApiProblem(404, "preview_file_not_found", "Preview file was not found.")
    zip_bytes, actual_files, _ = backend._read_zip_object(
        bucket=backend._upload_bucket,
        key=_item_string(session, "source_key"),
        expected_sha256=_item_string(session, "source_sha256"),
    )
    if actual_files != expected_files:
        raise RuntimeError("Preview ZIP manifest does not match DynamoDB metadata")
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        try:
            data = archive.read(normalized)
        except KeyError as exc:
            raise ApiProblem(404, "preview_file_not_found", "Preview file was not found.") from exc
    return data, _content_type(normalized)


def require_visible(backend: Any, group_id: str, app_id: str) -> None:
    app = backend._require_app_in_group(app_id, group_id)
    if _visibility(app) == "hidden":
        raise ApiProblem(409, "app_hidden", "このアプリは現在非公開です。")


def record_launch(
    backend: Any,
    *,
    group_id: str,
    app_id: str,
    user_id: str,
) -> None:
    now = _now_iso()
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    stats_pk = f"APPSTATS#{app_id}"

    def update(sk: str, entity: str, extra_set: str, extra_values: dict[str, Any]) -> dict[str, Any]:
        return {
            "Update": {
                "TableName": backend._table_name,
                "Key": {"pk": _string_attr(stats_pk), "sk": _string_attr(sk)},
                "UpdateExpression": (
                    "SET entity = if_not_exists(entity, :entity), "
                    "app_id = if_not_exists(app_id, :app_id), "
                    "group_id = if_not_exists(group_id, :group_id), "
                    f"{extra_set}, updated_at = :updated_at ADD play_count :one"
                ),
                "ExpressionAttributeValues": {
                    ":entity": _string_attr(entity),
                    ":app_id": _string_attr(app_id),
                    ":group_id": _string_attr(group_id),
                    ":updated_at": _string_attr(now),
                    ":one": _number_attr(1),
                    **extra_values,
                },
            }
        }

    backend._dynamodb.transact_write_items(
        TransactItems=[
            update("TOTAL", "app_stats_total", "last_play_at = :updated_at", {}),
            update(
                f"MONTH#{month}",
                "app_stats_month",
                "month = if_not_exists(month, :month)",
                {":month": _string_attr(month)},
            ),
            update(
                f"USER#{user_id}",
                "app_stats_user",
                (
                    "user_id = if_not_exists(user_id, :user_id), "
                    "first_play_at = if_not_exists(first_play_at, :updated_at), "
                    "last_play_at = :updated_at"
                ),
                {":user_id": _string_attr(user_id)},
            ),
        ]
    )
