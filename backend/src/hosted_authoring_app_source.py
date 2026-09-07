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

    Built-ins use the immutable template ZIP in the upload bucket. Third-party
    editable apps use their currently published immutable artifact; draft source
    is never exposed through Authoring execution.
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

    published_version = _optional_number(app, "published_version")
    published_key = _optional_string(app, "published_key")
    published_sha256 = _optional_string(app, "published_sha256")
    if published_version is None or published_key is None or published_sha256 is None:
        raise ApiProblem(
            409,
            "authoring_app_unpublished",
            "This Authoring app must be published before other users can run it.",
        )
    files = _item_files(app, "published_files_json")
    zip_bytes, actual_files, actual_sha256 = backend._read_zip_object(
        bucket=backend._published_bucket,
        key=published_key,
        expected_sha256=published_sha256,
    )
    del zip_bytes
    if actual_files != files or actual_sha256 != published_sha256:
        raise RuntimeError("Published Authoring app source does not match metadata")
    _require_index(files)

    target = _optional_contract_string(app, "master_data_element_id")
    if require_master_data_target and target is None:
        raise ApiProblem(
            409,
            "player_master_data_target_missing",
            "The selected Player does not declare a Master Data injection target.",
        )
    return AuthoringAppSource(
        bucket=backend._published_bucket,
        key=published_key,
        files=tuple(files),
        sha256=published_sha256,
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
