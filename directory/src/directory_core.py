from __future__ import annotations

import hashlib
import ipaddress
import json
import re
import secrets
from dataclasses import dataclass
from typing import Any, Mapping
from urllib.parse import urlsplit

SCHEMA_VERSION = 1
API_PROTOCOL_VERSION = 1
CLASSROOM_CODE_LENGTH = 12
CLASSROOM_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ"
_TENANT_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_HOST_LABEL_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


@dataclass(frozen=True)
class DirectoryProblem(Exception):
    status_code: int
    code: str
    message: str

    def __str__(self) -> str:
        return self.message


def validate_tenant_id(value: object) -> str:
    if not isinstance(value, str) or _TENANT_ID_RE.fullmatch(value) is None:
        raise ValueError("tenant_id must be exactly 32 lowercase hexadecimal characters")
    return value


def normalize_classroom_code(value: object) -> str:
    if not isinstance(value, str) or len(value) > 64:
        raise ValueError("invalid classroom code")
    normalized = value.replace("-", "").upper()
    if len(normalized) != CLASSROOM_CODE_LENGTH:
        raise ValueError("invalid classroom code")
    if any(character not in CLASSROOM_CODE_ALPHABET for character in normalized):
        raise ValueError("invalid classroom code")
    return normalized


def hash_classroom_code(normalized_code: str) -> str:
    if len(normalized_code) != CLASSROOM_CODE_LENGTH:
        raise ValueError("classroom code must be normalized before hashing")
    return hashlib.sha256(normalized_code.encode("ascii")).hexdigest()


def generate_classroom_code() -> str:
    normalized = "".join(
        secrets.choice(CLASSROOM_CODE_ALPHABET)
        for _ in range(CLASSROOM_CODE_LENGTH)
    )
    return "-".join(normalized[index : index + 4] for index in range(0, 12, 4))


def generate_tenant_id() -> str:
    return secrets.token_hex(16)


def validate_display_name(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("display_name must be a string")
    value = value.strip()
    if not 1 <= len(value) <= 120:
        raise ValueError("display_name must contain 1-120 characters")
    if any(ord(character) < 0x20 for character in value):
        raise ValueError("display_name must not contain control characters")
    return value


def validate_api_base_url(value: object) -> str:
    if not isinstance(value, str) or not value or len(value) > 2048:
        raise ValueError("api_base_url must be a non-empty HTTPS URL")

    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise ValueError("api_base_url is malformed") from exc

    if parsed.scheme != "https":
        raise ValueError("api_base_url must use https")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("api_base_url must not contain user info")
    if not parsed.hostname:
        raise ValueError("api_base_url must include a host")
    if parsed.query or parsed.fragment:
        raise ValueError("api_base_url must not contain query or fragment")
    if parsed.path not in ("", "/"):
        raise ValueError("api_base_url path must be empty or /")
    if port not in (None, 443):
        raise ValueError("api_base_url must use the default HTTPS port")

    hostname = parsed.hostname.rstrip(".")
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        pass
    else:
        raise ValueError("api_base_url must not use an IP literal")

    lowered = hostname.lower()
    if lowered == "localhost" or lowered.endswith(".localhost"):
        raise ValueError("api_base_url must not use localhost")
    if lowered.endswith((".local", ".internal", ".lan", ".home")):
        raise ValueError("api_base_url must not use a local-only hostname")
    if "." not in hostname:
        raise ValueError("api_base_url host must be a public DNS name")
    try:
        hostname.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError("api_base_url host must be ASCII") from exc
    if any(_HOST_LABEL_RE.fullmatch(label) is None for label in hostname.split(".")):
        raise ValueError("api_base_url host is malformed")

    canonical_host = hostname.lower()
    return f"https://{canonical_host}"


def descriptor_from_tenant(
    tenant: Mapping[str, Any], *, valid_for_seconds: int
) -> dict[str, object]:
    if tenant.get("schema_version") != SCHEMA_VERSION:
        raise DirectoryProblem(
            409,
            "incompatible_tenant_config",
            "The tenant configuration schema is not supported.",
        )

    try:
        tenant_id = validate_tenant_id(tenant.get("tenant_id"))
        display_name = validate_display_name(tenant.get("display_name"))
        api_base_url = validate_api_base_url(tenant.get("api_base_url"))
        api_protocol_version = int(tenant.get("api_protocol_version"))
        config_revision = int(tenant.get("config_revision"))
    except (TypeError, ValueError) as exc:
        raise DirectoryProblem(
            409,
            "incompatible_tenant_config",
            "The tenant configuration is invalid.",
        ) from exc

    if api_protocol_version != API_PROTOCOL_VERSION or config_revision < 1:
        raise DirectoryProblem(
            409,
            "incompatible_tenant_config",
            "The tenant configuration is not compatible with this Directory.",
        )
    if not isinstance(valid_for_seconds, int) or valid_for_seconds < 1:
        raise RuntimeError("valid_for_seconds must be a positive integer")

    return {
        "schema_version": SCHEMA_VERSION,
        "tenant_id": tenant_id,
        "display_name": display_name,
        "api_base_url": api_base_url,
        "api_protocol_version": api_protocol_version,
        "config_revision": config_revision,
        "valid_for_seconds": valid_for_seconds,
    }


def strict_json_object(raw_body: object, *, expected_fields: set[str]) -> dict[str, Any]:
    if not isinstance(raw_body, str) or len(raw_body.encode("utf-8")) > 4096:
        raise DirectoryProblem(400, "invalid_request", "The request body is invalid.")
    try:
        payload = json.loads(raw_body)
    except (json.JSONDecodeError, UnicodeError) as exc:
        raise DirectoryProblem(400, "invalid_request", "The request body is not valid JSON.") from exc
    if not isinstance(payload, dict) or set(payload) != expected_fields:
        raise DirectoryProblem(
            400,
            "invalid_request",
            "The request body schema is invalid or contains unknown fields.",
        )
    return payload
