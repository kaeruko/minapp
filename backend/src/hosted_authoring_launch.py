from __future__ import annotations

import hashlib
import io
import re
import secrets
import time
import zipfile
from typing import Any

from app_zip import content_type as _content_type
from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_app_source import resolve_authoring_app_source
import hosted_authoring_session
from hosted_authoring_web_bridge import (
    HOST_ADAPTER_NATIVE,
    HOST_ADAPTER_WEB,
    inject_web_bridge,
    new_web_bridge_nonce,
    portal_origin_from_environment,
    validate_host_adapter,
)
from hosted_catalog_backend import (
    _files_json,
    _item_files,
    _optional_number,
)
from hosted_platform_backend import RUNTIME_SESSION_TTL_SECONDS, _number_attr

_AUTHORING_EDITOR_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
AUTHORING_EDITOR_CONTENT_SECONDS = hosted_authoring_session.AUTHORING_SESSION_SECONDS
AUTHORING_EDITOR_TTL_GRACE_SECONDS = hosted_authoring_session.AUTHORING_SESSION_TTL_GRACE_SECONDS


def create_launch(
    backend: Any,
    auth_subject: str,
    content_id: str,
    editor_app_id: str,
    *,
    host_adapter: str = HOST_ADAPTER_NATIVE,
) -> dict[str, Any]:
    """Mint Editor content, ephemeral Runtime, and Authoring capabilities atomically."""

    host_adapter = validate_host_adapter(host_adapter)
    web_parent_origin: str | None = None
    web_bridge_nonce: str | None = None
    if host_adapter == HOST_ADAPTER_WEB:
        # Validate the trusted parent before creating any capability/session.
        web_parent_origin = portal_origin_from_environment()
        web_bridge_nonce = new_web_bridge_nonce()

    now_epoch = int(time.time())
    authoring_result, authoring_item, user, editor = hosted_authoring_session.prepare_session(
        backend,
        auth_subject,
        content_id,
        editor_app_id,
        now_epoch=now_epoch,
    )
    group_id = _item_string(editor, "group_id")
    content_format = str(authoring_result["content_format"])
    source = resolve_authoring_app_source(
        backend,
        editor,
        require_master_data_target=False,
    )

    content_token = secrets.token_urlsafe(32)
    content_token_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
    runtime_token = secrets.token_urlsafe(32)
    runtime_token_hash = hashlib.sha256(runtime_token.encode("ascii")).hexdigest()
    authoring_token_hash = hosted_authoring_session._token_hash(
        str(authoring_result["token"])
    )
    preview_state_id = secrets.token_hex(32)

    content_expires_at = now_epoch + AUTHORING_EDITOR_CONTENT_SECONDS
    runtime_expires_at = now_epoch + RUNTIME_SESSION_TTL_SECONDS
    preview_state_ttl_epoch = (
        max(content_expires_at, runtime_expires_at) + AUTHORING_EDITOR_TTL_GRACE_SECONDS
    )

    content_item = {
        "pk": _string_attr(f"AUTHORINGEDITOR#{content_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("authoring_editor_content_session"),
        "host_adapter": _string_attr(host_adapter),
        "authoring_session_hash": _string_attr(authoring_token_hash),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "content_id": _string_attr(content_id),
        "content_format": _string_attr(content_format),
        "editor_app_id": _string_attr(editor_app_id),
        "source_bucket": _string_attr(source.bucket),
        "source_key": _string_attr(source.key),
        "source_sha256": _string_attr(source.sha256),
        "source_files_json": _string_attr(_files_json(list(source.files))),
        "source_version": _number_attr(source.version),
        "expires_at_epoch": _number_attr(content_expires_at),
        "ttl_epoch": _number_attr(
            content_expires_at + AUTHORING_EDITOR_TTL_GRACE_SECONDS
        ),
    }
    if host_adapter == HOST_ADAPTER_WEB:
        if web_parent_origin is None or web_bridge_nonce is None:
            raise RuntimeError("Validated Web Authoring launch lost bridge metadata")
        content_item["web_parent_origin"] = _string_attr(web_parent_origin)
        content_item["web_bridge_nonce"] = _string_attr(web_bridge_nonce)

    runtime_item = {
        "pk": _string_attr(f"RUNTIMESESSION#{runtime_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("runtime_session"),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(editor_app_id),
        "user_id": _string_attr(user.user_id),
        "expires_at_epoch": _number_attr(runtime_expires_at),
        "ttl_epoch": _number_attr(
            runtime_expires_at + AUTHORING_EDITOR_TTL_GRACE_SECONDS
        ),
        "preview_state_id": _string_attr(preview_state_id),
        "preview_state_ttl_epoch": _number_attr(preview_state_ttl_epoch),
    }

    backend._transact_put_new([authoring_item, content_item, runtime_item])
    result: dict[str, Any] = {
        "content_path": f"/hosted/authoring-editor/{content_token}/index.html",
        "content_expires_in": AUTHORING_EDITOR_CONTENT_SECONDS,
        "runtime_token": runtime_token,
        "runtime_expires_in": RUNTIME_SESSION_TTL_SECONDS,
        "authoring_token": authoring_result["token"],
        "authoring_expires_in": authoring_result["expires_in"],
        "content_id": content_id,
        "content_format": content_format,
        "editor_app_id": editor_app_id,
        "allowed_operations": authoring_result["allowed_operations"],
    }
    if host_adapter == HOST_ADAPTER_WEB:
        if web_bridge_nonce is None:
            raise RuntimeError("Validated Web Authoring launch lost its bridge nonce")
        result["web_bridge_nonce"] = web_bridge_nonce
    return result


def get_editor_file(
    backend: Any,
    token: str,
    path: str,
) -> tuple[bytes, str]:
    if not isinstance(token, str) or _AUTHORING_EDITOR_TOKEN_RE.fullmatch(token) is None:
        raise ApiProblem(
            404,
            "authoring_editor_content_not_found",
            "Authoring Editor content was not found or has expired.",
        )
    token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
    item = backend._get_item(pk=f"AUTHORINGEDITOR#{token_hash}", sk="META")
    now_epoch = int(time.time())
    if item is None or (_optional_number(item, "expires_at_epoch") or 0) <= now_epoch:
        raise ApiProblem(
            404,
            "authoring_editor_content_not_found",
            "Authoring Editor content was not found or has expired.",
        )
    if _item_string(item, "entity") != "authoring_editor_content_session":
        raise RuntimeError("Authoring Editor content key contains an unexpected entity")
    host_adapter = _item_string(item, "host_adapter")
    if host_adapter not in {HOST_ADAPTER_NATIVE, HOST_ADAPTER_WEB}:
        raise RuntimeError("Authoring Editor content has an unsupported host_adapter")

    authoring_hash = _item_string(item, "authoring_session_hash")
    authoring_item = backend._get_item(
        pk=f"AUTHORINGSESSION#{authoring_hash}",
        sk="META",
    )
    if (
        authoring_item is None
        or _item_string(authoring_item, "entity") != "authoring_session"
        or (_optional_number(authoring_item, "expires_at_epoch") or 0) <= now_epoch
    ):
        raise ApiProblem(
            404,
            "authoring_editor_content_not_found",
            "Authoring Editor content was not found or has expired.",
        )

    for field in ("user_id", "group_id", "content_id", "content_format", "editor_app_id"):
        if _item_string(item, field) != _item_string(authoring_item, field):
            raise RuntimeError(
                f"Authoring Editor content scope no longer matches Authoring session: {field}"
            )

    auth_subject = _item_string(authoring_item, "auth_subject")
    content_id = _item_string(item, "content_id")
    user, content = backend._owned_content(auth_subject, content_id)
    if user.user_id != _item_string(item, "user_id"):
        raise RuntimeError("Authoring Editor content user no longer matches owner")
    if _item_string(content, "group_id") != _item_string(item, "group_id"):
        raise RuntimeError("Authoring Editor content group no longer matches project")
    if _item_string(content, "content_format") != _item_string(item, "content_format"):
        raise RuntimeError("Authoring Editor content format no longer matches project")

    editor = backend._require_app_in_group(
        _item_string(item, "editor_app_id"),
        _item_string(item, "group_id"),
    )
    backend._require_not_deleting(editor)
    hosted_authoring_session._require_editor_support(
        editor,
        _item_string(item, "content_format"),
    )
    # Revalidate that the app is still a visible/published Authoring app, but
    # keep serving the immutable source version pinned when the session began.
    resolve_authoring_app_source(
        backend,
        editor,
        require_master_data_target=False,
    )

    source_bucket = _item_string(item, "source_bucket")
    if source_bucket not in {backend._upload_bucket, backend._published_bucket}:
        raise RuntimeError("Authoring Editor session contains an unexpected source bucket")
    normalized = backend._normalize_content_path(path)
    expected_files = _item_files(item, "source_files_json")
    if normalized not in expected_files:
        raise ApiProblem(
            404,
            "authoring_editor_file_not_found",
            "Authoring Editor file was not found.",
        )
    zip_bytes, actual_files, actual_sha256 = backend._read_zip_object(
        bucket=source_bucket,
        key=_item_string(item, "source_key"),
        expected_sha256=_item_string(item, "source_sha256"),
    )
    if actual_files != expected_files or actual_sha256 != _item_string(item, "source_sha256"):
        raise RuntimeError("Authoring Editor ZIP manifest does not match session metadata")
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        try:
            data = archive.read(normalized)
        except KeyError as exc:
            raise ApiProblem(
                404,
                "authoring_editor_file_not_found",
                "Authoring Editor file was not found.",
            ) from exc

    if host_adapter == HOST_ADAPTER_WEB and normalized == "index.html":
        data = inject_web_bridge(
            data,
            parent_origin=_item_string(item, "web_parent_origin"),
            bridge_nonce=_item_string(item, "web_bridge_nonce"),
        )
    return data, _content_type(normalized)
