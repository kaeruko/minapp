from __future__ import annotations

import sys
import unittest
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

DIRECTORY_SRC = Path(__file__).resolve().parents[1] / "src"
if str(DIRECTORY_SRC) not in sys.path:
    sys.path.insert(0, str(DIRECTORY_SRC))

from directory_admin import DirectoryAdminService  # noqa: E402
from directory_core import hash_classroom_code, normalize_classroom_code  # noqa: E402
from directory_store import DuplicateRecordError  # noqa: E402


class FakeAdminStore:
    def __init__(self) -> None:
        self.tenants: dict[str, dict[str, Any]] = {}
        self.codes: dict[str, dict[str, Any]] = {}
        self.audits: list[dict[str, Any]] = []

    def get_tenant(self, tenant_id: str) -> dict[str, Any] | None:
        tenant = self.tenants.get(tenant_id)
        return deepcopy(tenant) if tenant is not None else None

    def create_tenant(
        self,
        tenant: Mapping[str, Any],
        code_record: Mapping[str, Any],
        audit_record: Mapping[str, Any],
    ) -> None:
        tenant_id = str(tenant["tenant_id"])
        code_hash = str(code_record["code_hash"])
        if tenant_id in self.tenants or code_hash in self.codes:
            raise DuplicateRecordError("duplicate")
        self.tenants[tenant_id] = dict(tenant)
        self.codes[code_hash] = dict(code_record)
        self.audits.append(dict(audit_record))

    def update_endpoint(self, **kwargs: Any) -> None:
        tenant = self.tenants[kwargs["tenant_id"]]
        if tenant["config_revision"] != kwargs["expected_revision"]:
            raise RuntimeError("concurrent")
        tenant["api_base_url"] = kwargs["api_base_url"]
        tenant["api_protocol_version"] = kwargs["api_protocol_version"]
        tenant["config_revision"] += 1
        tenant["updated_at"] = kwargs["updated_at"]
        self.audits.append(dict(kwargs["audit_record"]))

    def set_status(self, **kwargs: Any) -> None:
        tenant = self.tenants[kwargs["tenant_id"]]
        if tenant["status"] != kwargs["current_status"]:
            raise RuntimeError("concurrent")
        tenant["status"] = kwargs["new_status"]
        tenant["updated_at"] = kwargs["updated_at"]
        self.audits.append(dict(kwargs["audit_record"]))

    def rotate_code(self, **kwargs: Any) -> None:
        tenant = self.tenants[kwargs["tenant_id"]]
        new_record = dict(kwargs["new_code_record"])
        new_hash = str(new_record["code_hash"])
        if new_hash in self.codes:
            raise DuplicateRecordError("duplicate code")
        old_hash = kwargs["old_code_hash"]
        old = self.codes[old_hash]
        old["status"] = "rotated"
        old["rotated_at"] = kwargs["updated_at"]
        self.codes[new_hash] = new_record
        tenant["current_code_hash"] = new_hash
        tenant["updated_at"] = kwargs["updated_at"]
        self.audits.append(dict(kwargs["audit_record"]))


class DirectoryAdminTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = FakeAdminStore()
        self.verifications: list[tuple[str, str, int]] = []

        def verifier(url: str, tenant_id: str, protocol: int) -> dict[str, Any]:
            self.verifications.append((url, tenant_id, protocol))
            return {
                "service": "minapp-tenant-api",
                "tenant_id": tenant_id,
                "api_protocol_version": protocol,
                "environment": "dev",
            }

        self.service = DirectoryAdminService(
            self.store,
            endpoint_verifier=verifier,
            tenant_id_factory=lambda: "a" * 32,
            code_factory=lambda: "7K2M-4Q9P-W6TX",
            now_factory=lambda: "2026-08-18T00:00:00Z",
        )

    def test_create_stores_only_code_hash_and_returns_raw_code_once(self) -> None:
        result = self.service.create_tenant("Test School")
        self.assertEqual(result["tenant_id"], "a" * 32)
        self.assertEqual(result["classroom_code"], "7K2M-4Q9P-W6TX")
        code_hash = hash_classroom_code(normalize_classroom_code(result["classroom_code"]))
        tenant = self.store.tenants["a" * 32]
        code = self.store.codes[code_hash]
        self.assertEqual(tenant["status"], "pending")
        self.assertEqual(code["status"], "active")
        self.assertNotIn("classroom_code", tenant)
        self.assertNotIn("classroom_code", code)
        self.assertNotIn(result["classroom_code"], repr(self.store.audits))

    def test_duplicate_tenant_or_code_is_rejected(self) -> None:
        self.service.create_tenant("Test School")
        with self.assertRaises(DuplicateRecordError):
            self.service.create_tenant("Another School")

    def test_endpoint_must_verify_before_activation(self) -> None:
        self.service.create_tenant("Test School")
        updated = self.service.update_endpoint(
            "a" * 32,
            "https://tenant.example.com/",
        )
        self.assertEqual(updated["config_revision"], 2)
        self.assertEqual(updated["api_base_url"], "https://tenant.example.com")
        activated = self.service.activate("a" * 32)
        self.assertEqual(activated["status"], "active")
        self.assertEqual(len(self.verifications), 2)
        self.assertEqual(self.store.tenants["a" * 32]["status"], "active")

    def test_rotate_code_invalidates_old_mapping_without_storing_raw_code(self) -> None:
        self.service.create_tenant("Test School")
        old_hash = self.store.tenants["a" * 32]["current_code_hash"]
        self.service.code_factory = lambda: "3MNP-5RST-7VWX"
        result = self.service.rotate_code("a" * 32)
        new_hash = hash_classroom_code(normalize_classroom_code(result["classroom_code"]))
        self.assertEqual(self.store.codes[old_hash]["status"], "rotated")
        self.assertEqual(self.store.codes[new_hash]["status"], "active")
        self.assertEqual(self.store.tenants["a" * 32]["current_code_hash"], new_hash)
        self.assertNotIn(result["classroom_code"], repr(self.store.tenants))
        self.assertNotIn(result["classroom_code"], repr(self.store.codes))
        self.assertNotIn(result["classroom_code"], repr(self.store.audits))

    def test_deactivate_transitions_active_tenant(self) -> None:
        self.service.create_tenant("Test School")
        self.service.update_endpoint("a" * 32, "https://tenant.example.com")
        self.service.activate("a" * 32)
        result = self.service.deactivate("a" * 32)
        self.assertEqual(result, {"tenant_id": "a" * 32, "status": "inactive"})
        self.assertEqual(self.store.tenants["a" * 32]["status"], "inactive")


if __name__ == "__main__":
    unittest.main()
