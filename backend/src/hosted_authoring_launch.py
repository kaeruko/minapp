from __future__ import annotations

import hashlib
import io
import re
import secrets
import time
import zipfile
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
import hosted_authoring_session
from hosted_catalog_backend import (
    _content_type,
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
) -> dict[str, Any]:
    """Mint Editor content, ephemeral Runtime, and Authoring capabilities atomically."""

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

    source_key, source_files, source_sha256 = _editor_source(backend, editor)

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
        "authoring_session_hash": _string_attr(authoring_token_hash),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "content_id": _string_attr(content_id),
        "content_format": _string_attr(content_format),
        "editor_app_id": _string_attr(editor_app_id),
        "source_key": _string_attr(source_key),
        "source_sha256": _string_attr(source_sha256),
        "source_files_json": _string_attr(_files_json(source_files)),
        "expires_at_epoch": _number_attr(content_expires_at),
        "ttl_epoch": _number_attr(
            content_expires_at + AUTHORING_EDITOR_TTL_GRACE_SECONDS
        ),
    }
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
    return {
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
    current_source_key, _, current_sha256 = _editor_source(backend, editor)
    if current_source_key != _item_string(item, "source_key"):
        raise RuntimeError("Authoring Editor source key changed during a live session")
    if current_sha256 != _item_string(item, "source_sha256"):
        raise RuntimeError("Authoring Editor source changed during a live session")

    normalized = backend._normalize_content_path(path)
    expected_files = _item_files(item, "source_files_json")
    if normalized not in expected_files:
        raise ApiProblem(
            404,
            "authoring_editor_file_not_found",
            "Authoring Editor file was not found.",
        )
    zip_bytes, actual_files, _ = backend._read_zip_object(
        bucket=backend._upload_bucket,
        key=_item_string(item, "source_key"),
        expected_sha256=_item_string(item, "source_sha256"),
    )
    if actual_files != expected_files:
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
    return data, _content_type(normalized)


def _editor_source(
    backend: Any,
    editor: dict[str, Any],
) -> tuple[str, list[str], str]:
    if _item_string(editor, "source_kind") != "builtin":
        raise ApiProblem(
            409,
            "editor_launch_source_unsupported",
            "This Editor source type is not yet supported for Authoring launch.",
        )
    builtin_id = _item_string(editor, "builtin_id")
    builtin_version = _optional_number(editor, "builtin_version")
    template = backend._hosted_builtin_templates().get(builtin_id)
    if template is None or builtin_version != template.get("version"):
        raise RuntimeError("Installed Authoring Editor references an unsupported template version")
    source_key = template.get("source_key")
    if not isinstance(source_key, str) or not source_key:
        raise RuntimeError("Authoring Editor template has no immutable source key")
    _, files, sha256 = backend._read_parent_source(editor)
    if not files or "index.html" not in files:
        raise RuntimeError("Authoring Editor source must contain index.html")
    return source_key, files, sha256
