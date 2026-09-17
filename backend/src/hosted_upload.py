from __future__ import annotations

import hashlib
import json
import uuid
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_manifest import AuthoringManifestContract, read_authoring_manifest
from hosted_catalog_backend import _files_json
from hosted_package_manifest import PackageManifest, read_package_manifest
from hosted_platform_backend import _now_iso, _number_attr
from zip_upload_normalization import normalize_uploaded_zip

_AUTHORING_METADATA_FIELDS = ("edits_json", "accepts_json", "master_data_element_id")


def _optional_item_string(item: dict[str, Any], field: str) -> str | None:
    raw = item.get(field)
    if raw is None:
        return None
    if not isinstance(raw, dict) or not isinstance(raw.get("S"), str) or not raw["S"]:
        raise RuntimeError(f"Hosted app field {field!r} is not a non-empty DynamoDB string")
    return raw["S"]


def _authoring_metadata(authoring: AuthoringManifestContract | None) -> dict[str, Any]:
    if authoring is None:
        return {}
    return {
        "edits_json": _string_attr(json.dumps(authoring.edits, separators=(",", ":"))),
        "accepts_json": _string_attr(json.dumps(authoring.accepts, separators=(",", ":"))),
        "master_data_element_id": (
            _string_attr(authoring.master_data_element_id)
            if authoring.master_data_element_id is not None
            else {"NULL": True}
        ),
    }


def _require_same_authoring_contract(
    existing: dict[str, Any], authoring: AuthoringManifestContract | None
) -> None:
    expected = _authoring_metadata(authoring)
    for field in _AUTHORING_METADATA_FIELDS:
        if existing.get(field) != expected.get(field):
            raise ApiProblem(
                409,
                "authoring_contract_changed",
                "The ZIP identifies an existing app but changes its Authoring contract. "
                "Create a new package identity for a different contract.",
            )


def _owned_upload_apps(backend: Any, owner_user_id: str, group_id: str) -> list[dict[str, Any]]:
    apps: list[dict[str, Any]] = []
    for item in backend._group_app_items(group_id):
        if _optional_item_string(item, "owner_user_id") != owner_user_id:
            continue
        if _optional_item_string(item, "source_kind") != "upload":
            continue
        if item.get("editable", {}).get("BOOL") is not True:
            continue
        if item.get("deletion_state") is not None:
            continue
        apps.append(item)
    return apps


def _single_match(matches: list[dict[str, Any]], *, error: str, message: str) -> dict[str, Any] | None:
    if not matches:
        return None
    if len(matches) != 1:
        raise ApiProblem(409, error, message)
    return matches[0]


def _require_matching_title(existing: dict[str, Any], title: str) -> None:
    existing_title = _item_string(existing, "title")
    if existing_title != title:
        raise ApiProblem(
            409,
            "package_title_mismatch",
            f"This ZIP belongs to the existing app {existing_title!r}; use that app title when updating it.",
        )


def _existing_upload_for(
    backend: Any,
    *,
    owner_user_id: str,
    group_id: str,
    title: str,
    sha256: str,
    package: PackageManifest | None,
) -> dict[str, Any] | None:
    apps = _owned_upload_apps(backend, owner_user_id, group_id)

    if package is not None:
        matched = _single_match(
            [
                item
                for item in apps
                if _optional_item_string(item, "package_id") == package.package_id
            ],
            error="ambiguous_package_identity",
            message="Multiple existing apps have the same minapp-package.json package_id.",
        )
        if matched is not None:
            _require_matching_title(matched, title)
            return matched

    matched = _single_match(
        [item for item in apps if _optional_item_string(item, "source_sha256") == sha256],
        error="ambiguous_upload_content",
        message="Multiple existing apps have exactly the same ZIP content; remove duplicates before uploading it again.",
    )
    if matched is not None:
        _require_matching_title(matched, title)
        return matched

    same_title = [item for item in apps if _item_string(item, "title") == title]
    legacy_same_title = [
        item for item in same_title if _optional_item_string(item, "package_id") is None
    ]

    if package is not None:
        return _single_match(
            legacy_same_title,
            error="ambiguous_legacy_upload",
            message=(
                "Multiple legacy uploads have this title and no stable package identity; "
                "remove the duplicates before updating."
            ),
        )

    packaged_same_title = [
        item for item in same_title if _optional_item_string(item, "package_id") is not None
    ]
    if packaged_same_title:
        raise ApiProblem(
            409,
            "missing_package_identity",
            "An existing app with this title has a stable minapp-package.json identity. "
            "Use that app's original minapp-package.json when updating it.",
        )

    return _single_match(
        legacy_same_title,
        error="ambiguous_legacy_upload",
        message=(
            "Multiple legacy uploads have this title and no stable package identity; "
            "remove the duplicates before updating."
        ),
    )


def create_uploaded_app(
    backend: Any,
    auth_subject: str,
    group_id: str,
    title: str,
    zip_bytes: bytes,
) -> dict[str, Any]:
    """Create or update an editable Hosted app from a validated ZIP.

    A ZIP may contain ``minapp-package.json`` with a stable package_id. When
    that identity already belongs to one of the caller's editable uploads in
    the target group, the existing app receives a new source revision instead
    of a new app_id. Re-uploading byte-identical ZIP content is idempotent by
    normalized SHA-256. Legacy ZIPs without a package manifest may update a
    single same-title legacy upload; duplicate legacy titles fail explicitly
    instead of choosing an app heuristically.

    The caller only needs active membership in the target group. New apps are
    owned by that caller, and later source/preview/publish operations authorize
    against owner_user_id rather than group role.

    A common desktop packaging shape (one top-level folder containing
    index.html) is normalized to the canonical root-index ZIP before identity
    and checksum comparison. Ambiguous archive layouts still fail validation.

    If the canonical ZIP contains minapp.json, its Authoring contract is
    validated before any app data is written. An existing app may update source
    only when that contract remains unchanged.
    """
    normalized_zip, files = normalize_uploaded_zip(zip_bytes)
    authoring = read_authoring_manifest(normalized_zip)
    package = read_package_manifest(normalized_zip)
    sha256 = hashlib.sha256(normalized_zip).hexdigest()

    owner = backend._user_by_auth_subject(auth_subject)
    backend._require_active_membership(owner.user_id, group_id)

    existing = _existing_upload_for(
        backend,
        owner_user_id=owner.user_id,
        group_id=group_id,
        title=title,
        sha256=sha256,
        package=package,
    )
    if existing is not None:
        _require_same_authoring_contract(existing, authoring)
        if _item_string(existing, "source_sha256") == sha256:
            return backend._public_hosted_app(existing)

        app_id = _item_string(existing, "app_id")
        raw_revision = existing.get("source_revision", {}).get("N")
        if not isinstance(raw_revision, str):
            raise RuntimeError("Existing uploaded app has no source_revision")
        try:
            source_revision = int(raw_revision)
        except ValueError as exc:
            raise RuntimeError("Existing uploaded app source_revision is invalid") from exc
        if source_revision < 1:
            raise RuntimeError("Existing uploaded app source_revision is invalid")

        backend.update_editable_source(
            auth_subject,
            group_id,
            app_id,
            source_revision,
            normalized_zip,
        )
        updated = backend._require_app_in_group(app_id, group_id)
        return backend._public_hosted_app(updated)

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
    if package is not None:
        common["package_id"] = _string_attr(package.package_id)
    common.update(_authoring_metadata(authoring))

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
        zip_bytes=normalized_zip,
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
