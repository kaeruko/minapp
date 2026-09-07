from __future__ import annotations

import hashlib
import secrets
import time
from typing import Any

from aws_backend import _item_string, _string_attr
from hosted_app_management import (
    PREVIEW_SESSION_SECONDS,
    PREVIEW_TTL_GRACE_SECONDS,
    _owned_editable_app,
)
from hosted_catalog_backend import _files_json
from hosted_platform_backend import RUNTIME_SESSION_TTL_SECONDS, _number_attr


def create_preview_session(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> dict[str, Any]:
    user, app = _owned_editable_app(backend, auth_subject, app_id)
    group_id = _item_string(app, "group_id")
    source_revision = backend._source_revision(app)

    # Validate the immutable draft object before issuing either capability.
    _, files, sha256 = backend._read_current_source(app)
    source_key = _item_string(app, "source_key")

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
        "pk": _string_attr(f"HOSTEDPREVIEW#{content_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("hosted_preview_session"),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(app_id),
        "source_revision": _number_attr(source_revision),
        "source_key": _string_attr(source_key),
        "source_sha256": _string_attr(sha256),
        "source_files_json": _string_attr(_files_json(files)),
        "expires_at_epoch": _number_attr(content_expires_at),
        "ttl_epoch": _number_attr(content_expires_at + PREVIEW_TTL_GRACE_SECONDS),
    }
    runtime_session = {
        "pk": _string_attr(f"RUNTIMESESSION#{runtime_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("runtime_session"),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(app_id),
        "user_id": _string_attr(user.user_id),
        "expires_at_epoch": _number_attr(runtime_expires_at),
        "ttl_epoch": _number_attr(runtime_expires_at + PREVIEW_TTL_GRACE_SECONDS),
        "preview_state_id": _string_attr(preview_state_id),
        "preview_state_ttl_epoch": _number_attr(preview_state_ttl_epoch),
    }

    # Content and Runtime capabilities are all-or-nothing. A failure must not
    # leave a preview URL whose state token was never created.
    backend._transact_put_new([content_session, runtime_session])

    return {
        "app_id": app_id,
        "group_id": group_id,
        "source_revision": source_revision,
        "content_path": f"/hosted/preview/{content_token}/index.html",
        "expires_in": PREVIEW_SESSION_SECONDS,
        "runtime_token": runtime_token,
        "runtime_expires_in": RUNTIME_SESSION_TTL_SECONDS,
    }
