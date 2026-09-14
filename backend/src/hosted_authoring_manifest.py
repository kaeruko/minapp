from __future__ import annotations

import io
import json
import re
import zipfile
from dataclasses import dataclass
from typing import Any

from errors import ApiProblem
from hosted_authoring_backend import validate_content_format

AUTHORING_MANIFEST_PATH = "minapp.json"
MAX_AUTHORING_MANIFEST_BYTES = 64 * 1024
_MASTER_DATA_ELEMENT_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.:-]{0,127}$")


@dataclass(frozen=True)
class AuthoringManifestContract:
    edits: tuple[str, ...]
    accepts: tuple[str, ...]
    master_data_element_id: str | None


def read_authoring_manifest(zip_bytes: bytes) -> AuthoringManifestContract | None:
    """Return the strict Authoring contract declared by a canonical app ZIP.

    A missing minapp.json means that the ZIP is an ordinary app. Once the
    manifest exists, every malformed or unsupported value is an explicit
    error; callers must never fall back to ordinary-app behavior.
    """
    if not isinstance(zip_bytes, bytes):
        raise TypeError("zip_bytes must be bytes")

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        try:
            info = archive.getinfo(AUTHORING_MANIFEST_PATH)
        except KeyError:
            return None
        if info.file_size > MAX_AUTHORING_MANIFEST_BYTES:
            raise _invalid("minapp.json is too large.")
        raw = archive.read(info)

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise _invalid("minapp.json must be UTF-8 JSON.") from exc
    try:
        document = json.loads(text)
    except json.JSONDecodeError as exc:
        raise _invalid("minapp.json must contain valid JSON.") from exc

    if not isinstance(document, dict):
        raise _invalid("minapp.json root must be an object.")
    if set(document) != {"authoring"}:
        raise _invalid("minapp.json must contain exactly the authoring field.")

    authoring = document["authoring"]
    if not isinstance(authoring, dict):
        raise _invalid("authoring must be an object.")
    expected_fields = {"edits", "accepts", "master_data_element_id"}
    if set(authoring) != expected_fields:
        raise _invalid(
            "authoring must contain exactly edits, accepts, and master_data_element_id."
        )

    edits = _formats(authoring["edits"], "edits")
    accepts = _formats(authoring["accepts"], "accepts")
    if not edits and not accepts:
        raise _invalid("authoring must declare at least one edits or accepts format.")

    target = authoring["master_data_element_id"]
    if accepts:
        if not isinstance(target, str) or _MASTER_DATA_ELEMENT_ID_RE.fullmatch(target) is None:
            raise _invalid(
                "authoring with accepts requires a valid master_data_element_id."
            )
    else:
        if target is not None:
            raise _invalid(
                "master_data_element_id must be null when accepts is empty."
            )

    return AuthoringManifestContract(
        edits=edits,
        accepts=accepts,
        master_data_element_id=target,
    )


def _formats(value: Any, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise _invalid(f"authoring.{field} must be a string array.")
    if len(set(value)) != len(value):
        raise _invalid(f"authoring.{field} must not contain duplicates.")

    formats: list[str] = []
    for content_format in value:
        try:
            formats.append(validate_content_format(content_format))
        except ApiProblem as exc:
            raise _invalid(
                f"authoring.{field} contains an invalid content format."
            ) from exc
    return tuple(formats)


def _invalid(message: str) -> ApiProblem:
    return ApiProblem(400, "invalid_authoring_manifest", message)
