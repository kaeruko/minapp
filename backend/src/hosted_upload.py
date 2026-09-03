from __future__ import annotations

import hashlib
import uuid
from typing import Any

from aws_backend import _string_attr
from hosted_catalog_backend import _files_json
from hosted_platform_backend import _now_iso, _number_attr
from phase2_backend import _safe_zip_paths


def create_uploaded_app(
    backend: Any,
    auth_subject: str,
    group_id: str,
    title: str,
    zip_bytes: bytes,
) -> dict[str, Any]:
    """Create a new editable Hosted app directly from a validated ZIP.

    This deliberately does not fork or install a hidden built-in app. The ZIP
    supplied by the caller becomes source revision 1 of an independent app.
    Existing Hosted source validation, S3 immutability, app-capacity checks,
    and owner authorization are reused without fallback behavior.
    """
    files = _safe_zip_paths(zip_bytes)
    sha256 = hashlib.sha256(zip_bytes).hexdigest()

    owner = backend._user_by_auth_subject(auth_subject)
    backend._require_owner_group(owner.user_id, group_id)
    backend._require_app_capacity(group_id)

    app_id = uuid.uuid4().hex
    created_at = _now_iso()
    source_revision = 1
    source_key = backend._draft_source_key(group_id, app_id, source_revision)
    common: dict[str, Any] = {
        "entity": _string_attr("app"),
        "app_id": _string_attr(app_id),
        "group_id": _string_attr(group_id),
        "title": _string_attr(title),
        "owner_user_id": _string_attr(owner.user_id),
        "source_kind": _string_attr("upload"),
        "editable": {"BOOL": True},
        "source_revision": _number_attr(source_revision),
        "source_key": _string_attr(source_key),
        "source_sha256": _string_attr(sha256),
        "source_files_json": _string_attr(_files_json(files)),
        "source_updated_at": _string_attr(created_at),
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

    source_version_id = backend._put_immutable_zip(
        bucket=backend._upload_bucket,
        key=source_key,
        zip_bytes=zip_bytes,
        sha256=sha256,
    )
    source_manifest = backend._source_manifest(
        app_id=app_id,
        group_id=group_id,
        revision=source_revision,
        source_key=source_key,
        s3_version_id=source_version_id,
        sha256=sha256,
        files=files,
        created_at=created_at,
    )
    try:
        backend._transact_put_new([app_meta, group_index, source_manifest])
    except Exception:
        backend._delete_failed_write(
            backend._upload_bucket,
            source_key,
            source_version_id,
            "Uploaded app metadata creation",
        )
        raise
    return backend._public_hosted_app(app_meta)
