from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _string_attr  # noqa: E402
from hosted_authoring_app_contracts import list_authoring_app_contracts  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class HostedAuthoringAppContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = AuthoringFakeDynamoDb()
        self.runtime = AuthoringFakeDynamoDb()
        self.s3 = FakeS3()
        self.backend = HostedAuthoringIndexedBackend(
            cognito=self.cognito,
            dynamodb=self.metadata,
            runtime_dynamodb=self.runtime,
            s3=self.s3,
            user_pool_id="pool",
            app_client_id="client",
            table_name="metadata",
            runtime_table_name="runtime",
            upload_bucket="uploads",
            published_bucket="published",
        )
        self.backend.register("alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.subject = self.cognito.users["alice"]["sub"]
        self.group = self.backend.create_group(self.subject, "創作部")
        self.group_id = str(self.group["group_id"])

    def test_lists_only_installed_authoring_capable_apps(self) -> None:
        editor = self.backend.install_builtin(self.subject, self.group_id, "novel-editor")
        player = self.backend.install_builtin(self.subject, self.group_id, "novel-starter")
        self.backend.install_builtin(self.subject, self.group_id, "shiba-game")

        apps = list_authoring_app_contracts(self.backend, self.subject, self.group_id)

        self.assertEqual({app["app_id"] for app in apps}, {editor["app_id"], player["app_id"]})
        editor_contract = next(app for app in apps if app["app_id"] == editor["app_id"])
        player_contract = next(app for app in apps if app["app_id"] == player["app_id"])
        self.assertEqual(
            set(editor_contract),
            {"app_id", "group_id", "title", "edits", "accepts"},
        )
        self.assertEqual(editor_contract["group_id"], self.group_id)
        self.assertEqual(editor_contract["edits"], ["minapp/novel@1"])
        self.assertEqual(editor_contract["accepts"], [])
        self.assertEqual(player_contract["edits"], [])
        self.assertEqual(player_contract["accepts"], ["minapp/novel@1"])

    def test_corrupt_contract_fails_instead_of_disappearing_from_discovery(self) -> None:
        editor = self.backend.install_builtin(self.subject, self.group_id, "novel-editor")
        index = self.metadata.items[(f"GROUP#{self.group_id}", f"APP#{editor['app_id']}")]
        index["edits_json"] = _string_attr('["not-versioned"]')

        with self.assertRaisesRegex(RuntimeError, "invalid content format"):
            list_authoring_app_contracts(self.backend, self.subject, self.group_id)


if __name__ == "__main__":
    unittest.main()
