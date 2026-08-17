from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from tenant_identity import TenantIdentity  # noqa: E402


class TenantIdentityTests(unittest.TestCase):
    def test_valid_environment_is_exposed_without_secrets(self) -> None:
        identity = TenantIdentity.from_environment(
            {
                "TENANT_ID": "a" * 32,
                "API_PROTOCOL_VERSION": "1",
                "ENVIRONMENT": "dev",
                "USER_POOL_ID": "must-not-leak",
                "AWS_ACCOUNT_ID": "must-not-leak",
            }
        )
        self.assertEqual(
            identity.public_payload(),
            {
                "service": "minapp-tenant-api",
                "tenant_id": "a" * 32,
                "api_protocol_version": 1,
                "environment": "dev",
            },
        )

    def test_two_deployments_keep_distinct_identities(self) -> None:
        first = TenantIdentity.from_environment(
            {
                "TENANT_ID": "1" * 32,
                "API_PROTOCOL_VERSION": "1",
                "ENVIRONMENT": "prod",
            }
        )
        second = TenantIdentity.from_environment(
            {
                "TENANT_ID": "2" * 32,
                "API_PROTOCOL_VERSION": "1",
                "ENVIRONMENT": "prod",
            }
        )
        self.assertNotEqual(first.tenant_id, second.tenant_id)

    def test_invalid_or_missing_tenant_id_fails(self) -> None:
        for value in (None, "", "A" * 32, "a" * 31, "not-a-tenant"):
            environment = {
                "API_PROTOCOL_VERSION": "1",
                "ENVIRONMENT": "dev",
            }
            if value is not None:
                environment["TENANT_ID"] = value
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                TenantIdentity.from_environment(environment)

    def test_invalid_protocol_version_fails(self) -> None:
        for value in (None, "", "0", "1.0", "x"):
            environment = {
                "TENANT_ID": "a" * 32,
                "ENVIRONMENT": "dev",
            }
            if value is not None:
                environment["API_PROTOCOL_VERSION"] = value
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                TenantIdentity.from_environment(environment)


if __name__ == "__main__":
    unittest.main()
