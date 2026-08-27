from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_legal_backend import HostedLegalBackend  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402


class HostedLegalBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.backend = HostedLegalBackend(
            cognito=self.cognito,
            dynamodb=self.dynamo,
            runtime_dynamodb=self.dynamo,
            user_pool_id="pool",
            app_client_id="client",
            table_name="table",
            runtime_table_name="runtime-table",
        )

    def test_registration_persists_versions_and_server_timestamp(self) -> None:
        result = self.backend.register(
            "alice",
            "secret12",
            TERMS_VERSION,
            PRIVACY_VERSION,
        )
        user_id = result["user_id"]
        subject = self.cognito.users["alice"]["sub"]

        user_item = self.dynamo.items[(f"USER#{user_id}", "PROFILE")]
        auth_item = self.dynamo.items[(f"AUTH#{subject}", "PROFILE")]
        for item in (user_item, auth_item):
            self.assertEqual(item["terms_version"]["S"], TERMS_VERSION)
            self.assertEqual(item["privacy_version"]["S"], PRIVACY_VERSION)
            self.assertIs(item["terms_accepted"]["BOOL"], True)
            self.assertIs(item["privacy_accepted"]["BOOL"], True)
            self.assertRegex(item["terms_accepted_at"]["S"], r"^\d{4}-\d{2}-\d{2}T")
            self.assertEqual(
                item["terms_accepted_at"]["S"],
                item["privacy_accepted_at"]["S"],
            )

        self.assertEqual(result["legal"]["terms_version"], TERMS_VERSION)
        self.assertEqual(result["legal"]["privacy_version"], PRIVACY_VERSION)
        self.assertEqual(result["legal"]["accepted_at"], user_item["terms_accepted_at"]["S"])
        self.assertIn("recovery_code", result)

    def test_backend_rejects_stale_versions_even_if_handler_is_bypassed(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            self.backend.register(
                "alice",
                "secret12",
                "stale-terms",
                PRIVACY_VERSION,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "terms_version_outdated")
        self.assertEqual(self.cognito.users, {})
        self.assertEqual(self.dynamo.items, {})


if __name__ == "__main__":
    unittest.main()
