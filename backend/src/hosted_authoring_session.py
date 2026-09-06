from __future__ import annotations

import hashlib
import json
import re
import secrets
import time
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_backend import validate_content_format
from hosted_catalog_backend import _optional_number
from hosted_platform_backend import _number_attr

AUTHORING_SESSION_SECONDS = 10 * 60
AUTHORING_SESSION_TTL_GRACE_SECONDS = 24 * 60 * 60
MAX_AUTHORING_REQUESTS_PER_SESSION = 300
_AUTHORING_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
_APP_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_ALLOWED_OPERATIONS = (
    "load",
    "save_document",
    "get_asset",
    "save_asset",
    "delete_asset",
    "publish_request",
)


def create_session(
    backend: Any,
    auth_subject: str,
    content_id: str,
    editor_app_id: str,
) -> dict[str, Any]:
    if not isinstance(editor_app_id, str) or _APP_ID_RE.fullmatch(editor_app_id) is None:
        raise ApiProblem(404, "app_not_found", "Authoring Editor app was not found.")

    user, content = backend._owned_content(auth_subject, content_id)
    group_id = _item_string(content, "group_id")
    content_format = _item_string(content, "content_format")
    editor = backend._require_app_in_group(editor_app_id, group_id)
    backend._require_not_deleting(editor)
    _require_editor_support(editor, content_format)

    token = secrets.token_urlsafe(32)
    token_hash = _token_hash(token)
    now_epoch = int(time.time())
    expires_at = now_epoch + AUTHORING_SESSION_SECONDS
    item = {
        "pk": _string_attr(f"AUTHORINGSESSION#{token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("authoring_session"),
        "auth_subject": _string_attr(auth_subject),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "content_id": _string_attr(content_id),
        "content_format": _string_attr(content_format),
        "editor_app_id": _string_attr(editor_app_id),
        "allowed_operations_json": _string_attr(
            json.dumps(_ALLOWED_OPERATIONS, separators=(",", ":"))
        ),
        "request_count": _number_attr(0),
        "expires_at_epoch": _number_attr(expires_at),
        "ttl_epoch": _number_attr(expires_at + AUTHORING_SESSION_TTL_GRACE_SECONDS),
    }
    backend._transact_put_new([item])
    return {
        "token": token,
        "expires_in": AUTHORING_SESSION_SECONDS,
        "content_id": content_id,
        "content_format": content_format,
        "editor_app_id": editor_app_id,
        "allowed_operations": list(_ALLOWED_OPERATIONS),
    }


def load_project(backend: Any, token: str) -> dict[str, Any]:
    context = _consume_session(backend, token, "load")
    return backend.load_authoring_project(context[0], context[1])


def save_document(
    backend: Any,
    token: str,
    *,
    expected_revision: int,
    document: dict[str, Any],
) -> dict[str, Any]:
    context = _consume_session(backend, token, "save_document")
    return backend.save_authoring_document(
        context[0],
        context[1],
        expected_revision=expected_revision,
        document=document,
    )


def get_asset(backend: Any, token: str, path: str) -> tuple[bytes, str]:
    context = _consume_session(backend, token, "get_asset")
    return backend.get_authoring_asset(context[0], context[1], path)


def save_asset(
    backend: Any,
    token: str,
    *,
    expected_revision: int,
    path: str,
    data: bytes,
) -> dict[str, Any]:
    context = _consume_session(backend, token, "save_asset")
    return backend.save_authoring_asset(
        context[0],
        context[1],
        expected_revision=expected_revision,
        path=path,
        data=data,
    )


def delete_asset(
    backend: Any,
    token: str,
    *,
    expected_revision: int,
    path: str,
) -> dict[str, Any]:
    context = _consume_session(backend, token, "delete_asset")
    return backend.delete_authoring_asset(
        context[0],
        context[1],
        expected_revision=expected_revision,
        path=path,
    )


def publish_project(
    backend: Any,
    token: str,
    *,
    expected_revision: int,
) -> dict[str, Any]:
    context = _consume_session(backend, token, "publish_request")
    return backend.publish_authoring_project(
        context[0],
        context[1],
        expected_revision=expected_revision,
    )


def _consume_session(
    backend: Any,
    token: str,
    operation: str,
) -> tuple[str, str]:
    item = _session_item(backend, token)
    now_epoch = int(time.time())
    expires_at = _optional_number(item, "expires_at_epoch")
    if expires_at is None or expires_at <= now_epoch:
        raise ApiProblem(
            404,
            "authoring_session_not_found",
            "Authoring session was not found or has expired.",
        )

    allowed = _allowed_operations(item)
    if operation not in allowed:
        raise ApiProblem(
            403,
            "authoring_operation_not_allowed",
            "This Authoring session does not allow the requested operation.",
        )

    auth_subject = _item_string(item, "auth_subject")
    user_id = _item_string(item, "user_id")
    content_id = _item_string(item, "content_id")
    group_id = _item_string(item, "group_id")
    content_format = _item_string(item, "content_format")
    editor_app_id = _item_string(item, "editor_app_id")

    user, content = backend._owned_content(auth_subject, content_id)
    if user.user_id != user_id:
        raise RuntimeError("Authoring session user no longer matches authenticated subject")
    if _item_string(content, "group_id") != group_id:
        raise RuntimeError("Authoring session group no longer matches content")
    if _item_string(content, "content_format") != content_format:
        raise RuntimeError("Authoring session format no longer matches content")

    editor = backend._require_app_in_group(editor_app_id, group_id)
    backend._require_not_deleting(editor)
    _require_editor_support(editor, content_format)
    _consume_request_budget(backend, token, now_epoch)
    return auth_subject, content_id


def _session_item(backend: Any, token: str) -> dict[str, Any]:
    if not isinstance(token, str) or _AUTHORING_TOKEN_RE.fullmatch(token) is None:
        raise ApiProblem(
            404,
            "authoring_session_not_found",
            "Authoring session was not found or has expired.",
        )
    item = backend._get_item(pk=f"AUTHORINGSESSION#{_token_hash(token)}", sk="META")
    if item is None:
        raise ApiProblem(
            404,
            "authoring_session_not_found",
            "Authoring session was not found or has expired.",
        )
    if _item_string(item, "entity") != "authoring_session":
        raise RuntimeError("Authoring session key contains an unexpected entity")
    return item


def _consume_request_budget(backend: Any, token: str, now_epoch: int) -> None:
    try:
        backend._dynamodb.update_item(
            TableName=backend._table_name,
            Key={
                "pk": _string_attr(f"AUTHORINGSESSION#{_token_hash(token)}"),
                "sk": _string_attr("META"),
            },
            UpdateExpression="SET request_count = request_count + :one",
            ConditionExpression=(
                "attribute_exists(pk) AND request_count < :limit AND "
                "expires_at_epoch > :now"
            ),
            ExpressionAttributeValues={
                ":one": _number_attr(1),
                ":limit": _number_attr(MAX_AUTHORING_REQUESTS_PER_SESSION),
                ":now": _number_attr(now_epoch),
            },
        )
    except Exception as exc:
        if _aws_error_code(exc) == "ConditionalCheckFailedException":
            raise ApiProblem(
                429,
                "authoring_request_limit_reached",
                "This Authoring session has reached its request limit. Start a new session.",
            ) from exc
        raise


def _require_editor_support(editor: dict[str, Any], content_format: str) -> None:
    formats = _editor_formats(editor)
    if content_format not in formats:
        raise ApiProblem(
            409,
            "editor_content_format_mismatch",
            f"The selected Editor does not declare support for {content_format}.",
        )


def _editor_formats(editor: dict[str, Any]) -> tuple[str, ...]:
    raw = editor.get("edits_json")
    if raw is None:
        raise ApiProblem(
            409,
            "editor_not_authoring_capable",
            "The selected app does not declare an Authoring edits contract.",
        )
    if not isinstance(raw, dict) or not isinstance(raw.get("S"), str):
        raise RuntimeError("Editor edits_json is not a DynamoDB string")
    try:
        value = json.loads(raw["S"])
    except json.JSONDecodeError as exc:
        raise RuntimeError("Editor edits_json is invalid JSON") from exc
    if (
        not isinstance(value, list)
        or not value
        or any(not isinstance(item, str) for item in value)
        or len(set(value)) != len(value)
    ):
        raise RuntimeError("Editor edits_json must be a unique non-empty string list")
    for declared in value:
        try:
            validate_content_format(declared)
        except ApiProblem as exc:
            raise RuntimeError("Editor declares an invalid content format") from exc
    return tuple(value)


def _allowed_operations(item: dict[str, Any]) -> tuple[str, ...]:
    raw = _item_string(item, "allowed_operations_json")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Authoring session allowed_operations_json is invalid JSON") from exc
    if (
        not isinstance(value, list)
        or not value
        or any(not isinstance(operation, str) for operation in value)
        or len(set(value)) != len(value)
    ):
        raise RuntimeError("Authoring session operations are invalid")
    return tuple(value)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()
