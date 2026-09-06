from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_authoring_session  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_authoring_backend import HostedAuthoringBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class HostedNovelEditorIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = AuthoringFakeDynamoDb()
        self.runtime = AuthoringFakeDynamoDb()
        self.s3 = FakeS3()
        self.backend = HostedAuthoringBackend(
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
        self.group = self.backend.create_group(self.subject, "ノベル制作部")

    def _create_project(self) -> dict[str, object]:
        return self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {
                "content_format": "minapp/novel@1",
                "schema_version": 1,
                "content_revision": 1,
                "title": "テスト作品",
                "start_scene": "opening",
                "assets": {},
                "characters": {},
                "scenes": {
                    "opening": {
                        "id": "opening",
                        "events": [
                            {"id": "end_1", "type": "end", "label": "END"}
                        ],
                    }
                },
            },
        )

    def test_installed_novel_editor_mints_authoring_session_for_exact_format(self) -> None:
        installed = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-editor",
        )
        app_id = installed["app_id"]
        app_item = self.metadata.items[(f"APP#{app_id}", "META")]

        self.assertEqual(
            json.loads(app_item["edits_json"]["S"]),
            ["minapp/novel@1"],
        )
        self.assertNotIn("accepts_json", app_item)
        self.assertNotIn("edits", installed)
        self.assertNotIn("edits_json", installed)

        project = self._create_project()
        session = hosted_authoring_session.create_session(
            self.backend,
            self.subject,
            project["content_id"],
            app_id,
        )

        self.assertEqual(session["content_id"], project["content_id"])
        self.assertEqual(session["content_format"], "minapp/novel@1")
        self.assertEqual(session["editor_app_id"], app_id)
        self.assertIn("load", session["allowed_operations"])
        self.assertIn("save_document", session["allowed_operations"])
        self.assertIn("publish_request", session["allowed_operations"])

    def test_installed_novel_player_is_not_accepted_as_editor(self) -> None:
        installed = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-starter",
        )
        app_id = installed["app_id"]
        app_item = self.metadata.items[(f"APP#{app_id}", "META")]
        self.assertEqual(
            json.loads(app_item["accepts_json"]["S"]),
            ["minapp/novel@1"],
        )
        self.assertNotIn("edits_json", app_item)

        project = self._create_project()
        with self.assertRaises(ApiProblem) as caught:
            hosted_authoring_session.create_session(
                self.backend,
                self.subject,
                project["content_id"],
                app_id,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "editor_not_authoring_capable")

    def test_builtin_catalog_does_not_expose_private_format_contract_fields_yet(self) -> None:
        builtins = self.backend.list_builtin_templates()
        editor = next(item for item in builtins if item["builtin_id"] == "novel-editor")
        player = next(item for item in builtins if item["builtin_id"] == "novel-starter")

        for item in (editor, player):
            self.assertNotIn("accepts", item)
            self.assertNotIn("edits", item)
            self.assertNotIn("source_key", item)


if __name__ == "__main__":
    unittest.main()
