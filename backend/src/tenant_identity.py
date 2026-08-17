from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Mapping

_TENANT_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_ENVIRONMENT_RE = re.compile(r"^[a-z][a-z0-9-]{1,15}$")


@dataclass(frozen=True)
class TenantIdentity:
    tenant_id: str
    api_protocol_version: int
    environment: str

    @classmethod
    def from_environment(cls, environ: Mapping[str, str]) -> "TenantIdentity":
        tenant_id = environ.get("TENANT_ID")
        if not isinstance(tenant_id, str) or _TENANT_ID_RE.fullmatch(tenant_id) is None:
            raise RuntimeError(
                "TENANT_ID must be exactly 32 lowercase hexadecimal characters."
            )

        raw_protocol_version = environ.get("API_PROTOCOL_VERSION")
        if not isinstance(raw_protocol_version, str) or not raw_protocol_version.isascii() or not raw_protocol_version.isdigit():
            raise RuntimeError("API_PROTOCOL_VERSION must be a positive ASCII integer.")
        api_protocol_version = int(raw_protocol_version)
        if api_protocol_version < 1:
            raise RuntimeError("API_PROTOCOL_VERSION must be at least 1.")

        environment = environ.get("ENVIRONMENT")
        if not isinstance(environment, str) or _ENVIRONMENT_RE.fullmatch(environment) is None:
            raise RuntimeError(
                "ENVIRONMENT must be 2-16 lowercase alphanumeric/hyphen characters and start with a letter."
            )

        return cls(
            tenant_id=tenant_id,
            api_protocol_version=api_protocol_version,
            environment=environment,
        )

    def public_payload(self) -> dict[str, object]:
        return {
            "service": "minapp-tenant-api",
            "tenant_id": self.tenant_id,
            "api_protocol_version": self.api_protocol_version,
            "environment": self.environment,
        }
