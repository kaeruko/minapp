from __future__ import annotations

import io
import json
import re
import zipfile
from dataclasses import dataclass

from errors import ApiProblem

PACKAGE_MANIFEST_PATH = "minapp-package.json"
MAX_PACKAGE_MANIFEST_BYTES = 16 * 1024
_PACKAGE_ID_RE = re.compile(r"^[0-9a-f]{32}$")


@dataclass(frozen=True)
class PackageManifest:
    package_id: str


def read_package_manifest(zip_bytes: bytes) -> PackageManifest | None:
    """Read the optional stable identity for a MinApp ZIP.

    minapp-package.json is deliberately separate from minapp.json, which is
    reserved for the Authoring contract. A missing package manifest keeps the
    legacy upload behavior. Once present, malformed data is an explicit error.
    """
    if not isinstance(zip_bytes, bytes):
        raise TypeError("zip_bytes must be bytes")

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        try:
            info = archive.getinfo(PACKAGE_MANIFEST_PATH)
        except KeyError:
            return None
        if info.file_size > MAX_PACKAGE_MANIFEST_BYTES:
            raise _invalid("minapp-package.json is too large.")
        raw = archive.read(info)

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise _invalid("minapp-package.json must be UTF-8 JSON.") from exc
    try:
        document = json.loads(text)
    except json.JSONDecodeError as exc:
        raise _invalid("minapp-package.json must contain valid JSON.") from exc

    if not isinstance(document, dict):
        raise _invalid("minapp-package.json root must be an object.")
    if set(document) != {"schema_version", "package_id"}:
        raise _invalid(
            "minapp-package.json must contain exactly schema_version and package_id."
        )
    if document["schema_version"] != 1:
        raise _invalid("minapp-package.json schema_version must be 1.")
    package_id = document["package_id"]
    if not isinstance(package_id, str) or _PACKAGE_ID_RE.fullmatch(package_id) is None:
        raise _invalid("minapp-package.json package_id must be 32 lowercase hex characters.")
    return PackageManifest(package_id=package_id)


def _invalid(message: str) -> ApiProblem:
    return ApiProblem(400, "invalid_package_manifest", message)
