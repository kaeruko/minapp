from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from aws_backend import _item_string
from errors import ApiProblem
from hosted_app_management import _visibility
from hosted_catalog_backend import _item_files, _optional_number, _optional_string


@dataclass(frozen=True)
class AuthoringAppSource:
    bucket: str
    key: str
    files: tuple[str, ...]
    sha256: str
    version: int
    master_data_element_id: str | None


def resolve_authoring_app_source(
    backend: Any,
    app: dict[str, Any],
    *,
    require_master_data_target: bool,
) -> AuthoringAppSource:
    """Resolve one immutable source revision for Editor/Player execution.

    Built-ins use their immutable template ZIP. Third-party editable apps are
    resolved through the current published manifest back to the exact immutable
    source revision that was published. A later draft is never exposed.
    """

    source_kind = _item_string(app, "source_kind")
    if source_kind == "builtin":
        builtin_id = _item_string(app, "builtin_id")
        builtin_version = _optional_number(app, "builtin_version")
        template = backend._hosted_builtin_templates().get(builtin_id)
        if template is None or builtin_version != template.get("version"):
            raise RuntimeError("Installed Authoring app references an unsupported template version")
        source_key = template.get("source_key")
        if not isinstance(source_key, str) or not source_key:
            raise RuntimeError("Authoring built-in template has no immutable source key")
        _, files, sha256 = backend._read_zip_object(
            bucket=backend._upload_bucket,
            key=source_key,
        )
        target = template.get("master_data_element_id")
        if target is not None and (not isinstance(target, str) or not target):
            raise RuntimeError("Authoring built-in has an invalid Master Data injection target")
        if require_master_data_target and target is None:
            raise ApiProblem(
                409,
                "player_master_data_target_missing",
                "The selected Player does not declare a Master Data injection target.",
            )
        _require_index(files)
        return AuthoringAppSource(
            bucket=backend._upload_bucket,
            key=source_key,
            files=tuple(files),
            sha256=sha256,
            version=int(builtin_version),
            master_data_element_id=target,
        )

    if source_kind not in {"upload", "fork"}:
        raise ApiProblem(
            409,
            "authoring_app_source_unsupported",
            f"Unsupported Authoring app source kind: {source_kind}.",
        )
    if _visibility(app) != "visible":
        raise ApiProblem(
            409,
            "authoring_app_hidden",
            "This Authoring app is not publicly available.",
        )

    app_id = _item_string(app, "app_id")
    group_id = _item_string(app, "group_id")
    published_version = _optional_number(app, "published_version")
    published_sha256 = _optional_string(app, "published_sha256")
    if published_version is None or published_sha256 is None:
        raise ApiProblem(
            409,
            "authoring_app_unpublished",
            "This Authoring app must be published before other users can run it.",
        )

    published_manifest = backend._get_item(
        pk=f"APP#{app_id}",
        sk=f"PUBLISHED#{published_version:06d}",
    )
    if published_manifest is None:
        raise RuntimeError("Published Authoring app manifest is missing")
    if _item_string(published_manifest, "entity") != "hosted_published_version":
        raise RuntimeError("Published Authoring app manifest has an unexpected entity")
    if _item_string(published_manifest, "app_id") != app_id or _item_string(
        published_manifest, "group_id"
    ) != group_id:
        raise RuntimeError("Published Authoring app manifest scope is invalid")
    source_revision = _optional_number(published_manifest, "source_revision")
    if source_revision is None:
        raise RuntimeError("Published Authoring app manifest has no source revision")
    if _item_string(published_manifest, "sha256") != published_sha256:
        raise RuntimeError("Published Authoring app checksum no longer matches its pointer")

    source_manifest = backend._get_item(
        pk=f"APP#{app_id}",
        sk=f"SOURCE#{source_revision:06d}",
    )
    if source_manifest is None:
        raise RuntimeError("Published Authoring app source manifest is missing")
    if _item_string(source_manifest, "entity") != "hosted_source_revision":
        raise RuntimeError("Published Authoring source manifest has an unexpected entity")
    if _item_string(source_manifest, "app_id") != app_id or _item_string(
        source_manifest, "group_id"
    ) != group_id:
        raise RuntimeError("Published Authoring source manifest scope is invalid")
    source_sha256 = _item_string(source_manifest, "source_sha256")
    if source_sha256 != published_sha256:
        raise RuntimeError("Published Authoring artifact differs from its source revision")
    files = _item_files(source_manifest, "source_files_json")
    if files != _item_files(published_manifest, "published_files_json"):
        raise RuntimeError("Published Authoring file manifest differs from its source revision")
    source_key = _item_string(source_manifest, "source_key")
    _, actual_files, actual_sha256 = backend._read_zip_object(
        bucket=backend._upload_bucket,
        key=source_key,
        expected_sha256=source_sha256,
    )
    if actual_files != files or actual_sha256 != source_sha256:
        raise RuntimeError("Immutable Authoring source revision does not match metadata")
    _require_index(files)

    target = _optional_contract_string(app, "master_data_element_id")
    if require_master_data_target and target is None:
        raise ApiProblem(
            409,
            "player_master_data_target_missing",
            "The selected Player does not declare a Master Data injection target.",
        )
    return AuthoringAppSource(
        bucket=backend._upload_bucket,
        key=source_key,
        files=tuple(files),
        sha256=source_sha256,
        version=int(published_version),
        master_data_element_id=target,
    )


def _optional_contract_string(item: dict[str, Any], field: str) -> str | None:
    raw = item.get(field)
    if raw is None or raw.get("NULL") is True:
        return None
    value = raw.get("S")
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"Authoring app {field} has invalid metadata")
    return value


def _require_index(files: list[str]) -> None:
    if not files or "index.html" not in files:
        raise RuntimeError("Authoring app source must contain index.html")
