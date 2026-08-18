from __future__ import annotations

import json
import secrets
from datetime import datetime, timezone
from typing import Any, Callable, Mapping, Protocol
from urllib.request import Request, urlopen

from directory_core import (
    API_PROTOCOL_VERSION,
    SCHEMA_VERSION,
    generate_classroom_code,
    generate_tenant_id,
    hash_classroom_code,
    normalize_classroom_code,
    validate_api_base_url,
    validate_display_name,
    validate_tenant_id,
)
from directory_store import DuplicateRecordError


class AdminStore(Protocol):
    def get_tenant(self, tenant_id: str) -> dict[str, Any] | None: ...

    def create_tenant(
        self,
        tenant: Mapping[str, Any],
        code_record: Mapping[str, Any],
        audit_record: Mapping[str, Any],
    ) -> None: ...

    def update_endpoint(self, **kwargs: Any) -> None: ...

    def set_status(self, **kwargs: Any) -> None: ...

    def rotate_code(self, **kwargs: Any) -> None: ...


EndpointVerifier = Callable[[str, str, int], Mapping[str, Any]]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _audit_record(tenant_id: str, action: str, timestamp: str) -> dict[str, Any]:
    return {
        "PK": f"AUDIT#{tenant_id}",
        "SK": f"{timestamp}#{secrets.token_hex(8)}",
        "entity": "audit",
        "tenant_id": tenant_id,
        "action": action,
        "created_at": timestamp,
    }


def verify_tenant_endpoint(
    api_base_url: str,
    expected_tenant_id: str,
    expected_protocol_version: int = API_PROTOCOL_VERSION,
) -> Mapping[str, Any]:
    base_url = validate_api_base_url(api_base_url)
    tenant_id = validate_tenant_id(expected_tenant_id)
    request = Request(
        base_url + "/tenant-info",
        headers={"Accept": "application/json", "User-Agent": "minapp-directory-admin/1"},
        method="GET",
    )
    with urlopen(request, timeout=10) as response:
        raw = response.read(16385)
        if len(raw) > 16384:
            raise RuntimeError("tenant-info response is too large")
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("tenant-info returned invalid JSON") from exc

    expected_fields = {
        "service",
        "tenant_id",
        "api_protocol_version",
        "environment",
    }
    if not isinstance(payload, dict) or set(payload) != expected_fields:
        raise RuntimeError("tenant-info schema mismatch")
    if payload.get("service") != "minapp-tenant-api":
        raise RuntimeError("tenant-info service mismatch")
    if payload.get("tenant_id") != tenant_id:
        raise RuntimeError("tenant-info tenant_id mismatch")
    if payload.get("api_protocol_version") != expected_protocol_version:
        raise RuntimeError("tenant-info protocol mismatch")
    environment = payload.get("environment")
    if not isinstance(environment, str) or not environment:
        raise RuntimeError("tenant-info environment is invalid")
    return payload


class DirectoryAdminService:
    def __init__(
        self,
        store: AdminStore,
        *,
        endpoint_verifier: EndpointVerifier = verify_tenant_endpoint,
        tenant_id_factory: Callable[[], str] = generate_tenant_id,
        code_factory: Callable[[], str] = generate_classroom_code,
        now_factory: Callable[[], str] = _utc_now,
    ) -> None:
        self.store = store
        self.endpoint_verifier = endpoint_verifier
        self.tenant_id_factory = tenant_id_factory
        self.code_factory = code_factory
        self.now_factory = now_factory

    def create_tenant(self, display_name: str) -> dict[str, str]:
        tenant_id = validate_tenant_id(self.tenant_id_factory())
        raw_code = self.code_factory()
        normalized_code = normalize_classroom_code(raw_code)
        code_hash = hash_classroom_code(normalized_code)
        now = self.now_factory()
        tenant = {
            "PK": f"TENANT#{tenant_id}",
            "SK": "META",
            "entity": "tenant",
            "schema_version": SCHEMA_VERSION,
            "tenant_id": tenant_id,
            "display_name": validate_display_name(display_name),
            "status": "pending",
            "api_protocol_version": API_PROTOCOL_VERSION,
            "config_revision": 1,
            "current_code_hash": code_hash,
            "created_at": now,
            "updated_at": now,
        }
        code_record = {
            "PK": f"CODE#{code_hash}",
            "SK": "META",
            "entity": "classroom_code",
            "code_hash": code_hash,
            "tenant_id": tenant_id,
            "status": "active",
            "created_at": now,
        }
        self.store.create_tenant(
            tenant,
            code_record,
            _audit_record(tenant_id, "tenant_created", now),
        )
        return {"tenant_id": tenant_id, "classroom_code": raw_code}

    def update_endpoint(self, tenant_id: str, api_base_url: str) -> dict[str, Any]:
        tenant_id = validate_tenant_id(tenant_id)
        endpoint = validate_api_base_url(api_base_url)
        tenant = self._required_tenant(tenant_id)
        self.endpoint_verifier(endpoint, tenant_id, API_PROTOCOL_VERSION)
        revision = self._revision(tenant)
        now = self.now_factory()
        self.store.update_endpoint(
            tenant_id=tenant_id,
            expected_revision=revision,
            api_base_url=endpoint,
            api_protocol_version=API_PROTOCOL_VERSION,
            updated_at=now,
            audit_record=_audit_record(tenant_id, "endpoint_updated", now),
        )
        return {
            "tenant_id": tenant_id,
            "api_base_url": endpoint,
            "config_revision": revision + 1,
        }

    def activate(self, tenant_id: str) -> dict[str, str]:
        tenant_id = validate_tenant_id(tenant_id)
        tenant = self._required_tenant(tenant_id)
        current_status = self._status(tenant)
        if current_status not in {"pending", "inactive"}:
            raise ValueError("tenant must be pending or inactive before activation")
        endpoint = validate_api_base_url(tenant.get("api_base_url"))
        self.endpoint_verifier(endpoint, tenant_id, API_PROTOCOL_VERSION)
        now = self.now_factory()
        self.store.set_status(
            tenant_id=tenant_id,
            current_status=current_status,
            new_status="active",
            updated_at=now,
            audit_record=_audit_record(tenant_id, "tenant_activated", now),
        )
        return {"tenant_id": tenant_id, "status": "active"}

    def deactivate(self, tenant_id: str) -> dict[str, str]:
        tenant_id = validate_tenant_id(tenant_id)
        tenant = self._required_tenant(tenant_id)
        current_status = self._status(tenant)
        if current_status == "inactive":
            raise ValueError("tenant is already inactive")
        now = self.now_factory()
        self.store.set_status(
            tenant_id=tenant_id,
            current_status=current_status,
            new_status="inactive",
            updated_at=now,
            audit_record=_audit_record(tenant_id, "tenant_deactivated", now),
        )
        return {"tenant_id": tenant_id, "status": "inactive"}

    def rotate_code(self, tenant_id: str) -> dict[str, str]:
        tenant_id = validate_tenant_id(tenant_id)
        tenant = self._required_tenant(tenant_id)
        old_code_hash = tenant.get("current_code_hash")
        if not isinstance(old_code_hash, str) or len(old_code_hash) != 64:
            raise RuntimeError("tenant current_code_hash is invalid")
        raw_code = self.code_factory()
        normalized_code = normalize_classroom_code(raw_code)
        new_code_hash = hash_classroom_code(normalized_code)
        if new_code_hash == old_code_hash:
            raise DuplicateRecordError("generated classroom code duplicates the current code")
        now = self.now_factory()
        new_code_record = {
            "PK": f"CODE#{new_code_hash}",
            "SK": "META",
            "entity": "classroom_code",
            "code_hash": new_code_hash,
            "tenant_id": tenant_id,
            "status": "active",
            "created_at": now,
        }
        self.store.rotate_code(
            tenant_id=tenant_id,
            old_code_hash=old_code_hash,
            new_code_record=new_code_record,
            updated_at=now,
            audit_record=_audit_record(tenant_id, "classroom_code_rotated", now),
        )
        return {"tenant_id": tenant_id, "classroom_code": raw_code}

    def _required_tenant(self, tenant_id: str) -> dict[str, Any]:
        tenant = self.store.get_tenant(tenant_id)
        if tenant is None:
            raise LookupError("tenant was not found")
        if tenant.get("schema_version") != SCHEMA_VERSION:
            raise RuntimeError("tenant schema_version is unsupported")
        return tenant

    @staticmethod
    def _status(tenant: Mapping[str, Any]) -> str:
        status = tenant.get("status")
        if status not in {"pending", "active", "inactive"}:
            raise RuntimeError("tenant status is invalid")
        return str(status)

    @staticmethod
    def _revision(tenant: Mapping[str, Any]) -> int:
        revision = tenant.get("config_revision")
        if not isinstance(revision, int) or revision < 1:
            raise RuntimeError("tenant config_revision is invalid")
        return revision
