from __future__ import annotations

import hashlib
import io
import json
import re
import secrets
import time
import zipfile
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_app_management import PREVIEW_SESSION_SECONDS, PREVIEW_TTL_GRACE_SECONDS
from hosted_authoring_backend import (
    MAX_AUTHORING_ASSET_BYTES,
    MAX_AUTHORING_DOCUMENT_BYTES,
    _asset_manifest_int,
    _asset_manifest_string,
    _item_assets,
    _required_item_number,
    validate_content_format,
)
from hosted_catalog_backend import _content_type, _files_json, _item_files, _optional_number
from hosted_platform_backend import RUNTIME_SESSION_TTL_SECONDS, _number_attr


_AUTHORING_PREVIEW_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
_APP_ID_RE = re.compile(r"^[0-9a-f]{32}$")


def create_preview(
    backend: Any,
    auth_subject: str,
    content_id: str,
    player_app_id: str,
    *,
    expected_revision: int,
) -> dict[str, Any]:
    if not isinstance(player_app_id, str) or _APP_ID_RE.fullmatch(player_app_id) is None:
        raise ApiProblem(404, "app_not_found", "Authoring Player app was not found.")
    if not isinstance(expected_revision, int) or isinstance(expected_revision, bool) or expected_revision < 1:
        raise ApiProblem(400, "invalid_expected_revision", "expected_revision must be a positive integer.")

    user, current = backend._owned_content(auth_subject, content_id)
    backend._require_expected_revision(current, expected_revision)
    group_id = _item_string(current, "group_id")
    content_format = _item_string(current, "content_format")

    manifest = _revision_manifest(backend, current, expected_revision)
    document_bytes = backend._read_object(
        key=_item_string(manifest, "document_key"),
        expected_sha256=_item_string(manifest, "document_sha256"),
        max_bytes=MAX_AUTHORING_DOCUMENT_BYTES,
    )
    if len(document_bytes) != _required_item_number(manifest, "document_bytes"):
        raise RuntimeError("Authoring preview document size does not match revision metadata")
    try:
        document = json.loads(document_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Authoring preview document is not valid UTF-8 JSON") from exc
    if not isinstance(document, dict):
        raise RuntimeError("Authoring preview document root is not an object")

    player = backend._require_app_in_group(player_app_id, group_id)
    backend._require_not_deleting(player)
    _require_player_support(player, content_format)
    source_key, source_files, source_sha256, master_data_element_id = _player_source(
        backend,
        player,
    )

    assets = _item_assets(manifest)
    collisions = sorted(set(source_files).intersection(assets))
    if collisions:
        raise ApiProblem(
            409,
            "authoring_preview_asset_collision",
            f"Authoring asset path collides with Player source: {collisions[0]}",
        )

    # Validate that the trusted Player has exactly one injection target before
    # minting any capability. Preview creation must fail atomically otherwise.
    source_zip, actual_files, actual_sha256 = backend._read_zip_object(
        bucket=backend._upload_bucket,
        key=source_key,
        expected_sha256=source_sha256,
    )
    if actual_files != source_files or actual_sha256 != source_sha256:
        raise RuntimeError("Authoring Player source changed before preview creation")
    with zipfile.ZipFile(io.BytesIO(source_zip)) as archive:
        try:
            index_html = archive.read("index.html")
        except KeyError as exc:
            raise RuntimeError("Authoring Player source has no index.html") from exc
    _compile_index_html(index_html, document, master_data_element_id)

    content_token = secrets.token_urlsafe(32)
    content_token_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
    runtime_token = secrets.token_urlsafe(32)
    runtime_token_hash = hashlib.sha256(runtime_token.encode("ascii")).hexdigest()
    preview_state_id = secrets.token_hex(32)
    now_epoch = int(time.time())
    content_expires_at = now_epoch + PREVIEW_SESSION_SECONDS
    runtime_expires_at = now_epoch + RUNTIME_SESSION_TTL_SECONDS
    preview_state_ttl_epoch = (
        max(content_expires_at, runtime_expires_at) + PREVIEW_TTL_GRACE_SECONDS
    )

    content_session = {
        "pk": _string_attr(f"AUTHORINGPREVIEW#{content_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("authoring_preview_session"),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "content_id": _string_attr(content_id),
        "content_format": _string_attr(content_format),
        "draft_revision": _number_attr(expected_revision),
        "document_key": _string_attr(_item_string(manifest, "document_key")),
        "document_sha256": _string_attr(_item_string(manifest, "document_sha256")),
        "document_bytes": _number_attr(_required_item_number(manifest, "document_bytes")),
        "assets_json": _string_attr(_item_string(manifest, "assets_json")),
        "player_app_id": _string_attr(player_app_id),
        "player_source_key": _string_attr(source_key),
        "player_source_sha256": _string_attr(source_sha256),
        "player_source_files_json": _string_attr(_files_json(source_files)),
        "master_data_element_id": _string_attr(master_data_element_id),
        "expires_at_epoch": _number_attr(content_expires_at),
        "ttl_epoch": _number_attr(content_expires_at + PREVIEW_TTL_GRACE_SECONDS),
    }
    runtime_session = {
        "pk": _string_attr(f"RUNTIMESESSION#{runtime_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("runtime_session"),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(player_app_id),
        "user_id": _string_attr(user.user_id),
        "expires_at_epoch": _number_attr(runtime_expires_at),
        "ttl_epoch": _number_attr(runtime_expires_at + PREVIEW_TTL_GRACE_SECONDS),
        "preview_state_id": _string_attr(preview_state_id),
        "preview_state_ttl_epoch": _number_attr(preview_state_ttl_epoch),
    }
    backend._transact_put_new([content_session, runtime_session])
    return {
        "content_id": content_id,
        "content_format": content_format,
        "draft_revision": expected_revision,
        "player_app_id": player_app_id,
        "content_path": f"/hosted/authoring-preview/{content_token}/index.html",
        "expires_in": PREVIEW_SESSION_SECONDS,
        "runtime_token": runtime_token,
        "runtime_expires_in": RUNTIME_SESSION_TTL_SECONDS,
    }


def get_preview_file(
    backend: Any,
    token: str,
    path: str,
) -> tuple[bytes, str]:
    item = _preview_item(backend, token)
    _revalidate_scope(backend, item)
    normalized = backend._normalize_content_path(path)

    source_files = _item_files(item, "player_source_files_json")
    assets = _item_assets(item)
    if normalized in source_files and normalized in assets:
        raise RuntimeError("Authoring preview contains a source/asset path collision")

    if normalized in source_files:
        source_zip, actual_files, actual_sha256 = backend._read_zip_object(
            bucket=backend._upload_bucket,
            key=_item_string(item, "player_source_key"),
            expected_sha256=_item_string(item, "player_source_sha256"),
        )
        if actual_files != source_files or actual_sha256 != _item_string(
            item, "player_source_sha256"
        ):
            raise RuntimeError("Authoring preview Player source no longer matches session")
        with zipfile.ZipFile(io.BytesIO(source_zip)) as archive:
            try:
                data = archive.read(normalized)
            except KeyError as exc:
                raise RuntimeError("Authoring preview Player ZIP manifest is inconsistent") from exc
        if normalized == "index.html":
            document_bytes = backend._read_object(
                key=_item_string(item, "document_key"),
                expected_sha256=_item_string(item, "document_sha256"),
                max_bytes=MAX_AUTHORING_DOCUMENT_BYTES,
            )
            if len(document_bytes) != _required_item_number(item, "document_bytes"):
                raise RuntimeError("Authoring preview document size changed")
            try:
                document = json.loads(document_bytes.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise RuntimeError("Authoring preview document is not valid UTF-8 JSON") from exc
            if not isinstance(document, dict):
                raise RuntimeError("Authoring preview document root is not an object")
            data = _compile_index_html(
                data,
                document,
                _item_string(item, "master_data_element_id"),
            )
        return data, _content_type(normalized)

    asset = assets.get(normalized)
    if asset is not None:
        data = backend._read_object(
            key=_asset_manifest_string(asset, "key"),
            expected_sha256=_asset_manifest_string(asset, "sha256"),
            max_bytes=MAX_AUTHORING_ASSET_BYTES,
        )
        if len(data) != _asset_manifest_int(asset, "bytes"):
            raise RuntimeError("Authoring preview asset size does not match revision metadata")
        return data, _asset_manifest_string(asset, "content_type")

    raise ApiProblem(404, "authoring_preview_file_not_found", "Authoring preview file was not found.")


def _preview_item(backend: Any, token: str) -> dict[str, Any]:
    if not isinstance(token, str) or _AUTHORING_PREVIEW_TOKEN_RE.fullmatch(token) is None:
        raise ApiProblem(
            404,
            "authoring_preview_not_found",
            "Authoring preview was not found or has expired.",
        )
    token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
    item = backend._get_item(pk=f"AUTHORINGPREVIEW#{token_hash}", sk="META")
    now_epoch = int(time.time())
    if item is None or (_optional_number(item, "expires_at_epoch") or 0) <= now_epoch:
        raise ApiProblem(
            404,
            "authoring_preview_not_found",
            "Authoring preview was not found or has expired.",
        )
    if _item_string(item, "entity") != "authoring_preview_session":
        raise RuntimeError("Authoring preview key contains an unexpected entity")
    return item


def _revalidate_scope(backend: Any, item: dict[str, Any]) -> None:
    content_id = _item_string(item, "content_id")
    meta = backend._get_item(pk=f"CONTENT#{content_id}", sk="META")
    if meta is None:
        raise ApiProblem(
            404,
            "authoring_preview_not_found",
            "Authoring preview was not found or has expired.",
        )
    for field in ("group_id", "owner_user_id", "content_format"):
        session_value = _item_string(item, "user_id") if field == "owner_user_id" else _item_string(item, field)
        if _item_string(meta, field) != session_value:
            raise RuntimeError(f"Authoring preview scope no longer matches content: {field}")
    if _item_string(meta, "status") != "draft":
        raise ApiProblem(409, "content_not_editable", "Authoring content is not editable.")

    revision = _required_item_number(item, "draft_revision")
    manifest = backend._get_item(pk=f"CONTENT#{content_id}", sk=f"REVISION#{revision:06d}")
    if manifest is None:
        raise RuntimeError("Authoring preview revision manifest disappeared")
    for field in (
        "content_id",
        "group_id",
        "content_format",
        "document_key",
        "document_sha256",
        "assets_json",
    ):
        if _item_string(manifest, field) != _item_string(item, field):
            raise RuntimeError(f"Authoring preview revision no longer matches session: {field}")
    if _required_item_number(manifest, "document_bytes") != _required_item_number(item, "document_bytes"):
        raise RuntimeError("Authoring preview document size no longer matches revision")

    player = backend._require_app_in_group(
        _item_string(item, "player_app_id"),
        _item_string(item, "group_id"),
    )
    backend._require_not_deleting(player)
    _require_player_support(player, _item_string(item, "content_format"))
    source_key, files, sha256, element_id = _player_source(backend, player)
    if source_key != _item_string(item, "player_source_key"):
        raise RuntimeError("Authoring preview Player source key changed during session")
    if sha256 != _item_string(item, "player_source_sha256"):
        raise RuntimeError("Authoring preview Player source changed during session")
    if files != _item_files(item, "player_source_files_json"):
        raise RuntimeError("Authoring preview Player file manifest changed during session")
    if element_id != _item_string(item, "master_data_element_id"):
        raise RuntimeError("Authoring preview Player injection target changed during session")


def _revision_manifest(
    backend: Any,
    current: dict[str, Any],
    revision: int,
) -> dict[str, Any]:
    content_id = _item_string(current, "content_id")
    manifest = backend._get_item(pk=f"CONTENT#{content_id}", sk=f"REVISION#{revision:06d}")
    if manifest is None:
        raise RuntimeError("Authoring revision manifest is missing")
    if _item_string(manifest, "entity") != "authoring_revision":
        raise RuntimeError("Authoring revision key contains an unexpected entity")
    if _required_item_number(manifest, "revision") != revision:
        raise RuntimeError("Authoring revision manifest has a mismatched revision")
    for field in ("content_id", "group_id", "owner_user_id", "content_format"):
        if _item_string(manifest, field) != _item_string(current, field):
            raise RuntimeError(f"Authoring revision manifest no longer matches content: {field}")
    return manifest


def _require_player_support(player: dict[str, Any], content_format: str) -> None:
    formats = _player_formats(player)
    if content_format not in formats:
        raise ApiProblem(
            409,
            "player_content_format_mismatch",
            f"The selected Player does not declare support for {content_format}.",
        )


def _player_formats(player: dict[str, Any]) -> tuple[str, ...]:
    raw = player.get("accepts_json")
    if raw is None:
        raise ApiProblem(
            409,
            "player_not_authoring_capable",
            "The selected app does not declare a Player accepts contract.",
        )
    if not isinstance(raw, dict) or not isinstance(raw.get("S"), str):
        raise RuntimeError("Player accepts_json is not a DynamoDB string")
    try:
        value = json.loads(raw["S"])
    except json.JSONDecodeError as exc:
        raise RuntimeError("Player accepts_json is invalid JSON") from exc
    if (
        not isinstance(value, list)
        or not value
        or any(not isinstance(item, str) for item in value)
        or len(set(value)) != len(value)
    ):
        raise RuntimeError("Player accepts_json must be a unique non-empty string list")
    for declared in value:
        try:
            validate_content_format(declared)
        except ApiProblem as exc:
            raise RuntimeError("Player declares an invalid content format") from exc
    return tuple(value)


def _player_source(
    backend: Any,
    player: dict[str, Any],
) -> tuple[str, list[str], str, str]:
    if _item_string(player, "source_kind") != "builtin":
        raise ApiProblem(
            409,
            "player_preview_source_unsupported",
            "This Player source type is not yet supported for structured preview.",
        )
    builtin_id = _item_string(player, "builtin_id")
    builtin_version = _optional_number(player, "builtin_version")
    template = backend._hosted_builtin_templates().get(builtin_id)
    if template is None or builtin_version != template.get("version"):
        raise RuntimeError("Installed Authoring Player references an unsupported template version")
    source_key = template.get("source_key")
    element_id = template.get("master_data_element_id")
    if not isinstance(source_key, str) or not source_key:
        raise RuntimeError("Authoring Player template has no immutable source key")
    if not isinstance(element_id, str) or not element_id:
        raise ApiProblem(
            409,
            "player_master_data_target_missing",
            "The selected Player does not declare a Master Data injection target.",
        )
    _, files, sha256 = backend._read_parent_source(player)
    if not files or "index.html" not in files:
        raise RuntimeError("Authoring Player source must contain index.html")
    return source_key, files, sha256, element_id


def _compile_index_html(
    source: bytes,
    document: dict[str, Any],
    element_id: str,
) -> bytes:
    try:
        html = source.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError("Authoring Player index.html must be UTF-8") from exc
    escaped_id = re.escape(element_id)
    pattern = re.compile(
        rf"(<script\b(?=[^>]*\bid=[\"']{escaped_id}[\"'])(?=[^>]*\btype=[\"']application/json[\"'])[^>]*>)(.*?)(</script\s*>)",
        re.IGNORECASE | re.DOTALL,
    )
    matches = list(pattern.finditer(html))
    if len(matches) != 1:
        raise RuntimeError(
            "Authoring Player must contain exactly one declared application/json Master Data element"
        )
    encoded = json.dumps(
        document,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    )
    encoded = (
        encoded.replace("&", "\\u0026")
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )
    match = matches[0]
    compiled = html[: match.start()] + match.group(1) + encoded + match.group(3) + html[match.end() :]
    return compiled.encode("utf-8")
