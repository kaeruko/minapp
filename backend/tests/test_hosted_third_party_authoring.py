from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_authoring_launch  # noqa: E402
import hosted_authoring_preview  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
import hosted_upload  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


FORMAT = "example/quiz@1"


def _zip(files: dict[str, str]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path, text in files.items():
            archive.writestr(path, text)
    return output.getvalue()


def editor_zip(version: str) -> bytes:
    return _zip(
        {
            "index.html": (
                "<!doctype html><title>Quiz Editor</title>"
                f"<div id='editor-marker'>{version}</div>"
                "<script src='editor.js'></script>"
            ),
            "editor.js": f"window.quizEditorVersion = '{version}';",
        }
    )


def player_zip(version: str) -> bytes:
    return _zip(
        {
            "index.html": (
                "<!doctype html><title>Quiz Player</title>"
                f"<div id='player-marker'>{version}</div>"
                "<script id='quiz-master-data' type='application/json'>{}</script>"
                "<script src='player.js'></script>"
            ),
            "player.js": f"window.quizPlayerVersion = '{version}';",
        }
    )


class ThirdPartyAuthoringRoundtripTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = AuthoringFakeDynamoDb()
        self.runtime = AuthoringFakeDynamoDb()
        self.s3 = FakeS3()
        common = dict(
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
        self.backend = HostedAuthoringIndexedBackend(**common)
        self.publisher = HostedAuthoringPublishBackend(**common)

        self.backend.register("alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.backend.register("bob", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.alice = self.cognito.users["alice"]["sub"]
        self.bob = self.cognito.users["bob"]["sub"]
        self.group = self.backend.create_group(self.alice, "Quiz Lab")
        invite = self.backend.create_invite(self.alice, self.group["group_id"])
        self.backend.join_group(self.bob, invite["code"])

        self.editor = hosted_upload.create_uploaded_app(
            self.backend,
            self.alice,
            self.group["group_id"],
            "Alice Quiz Editor",
            editor_zip("editor-v1"),
        )
        self.backend.register_authoring_contract(
            self.alice,
            self.group["group_id"],
            self.editor["app_id"],
            edits=[FORMAT],
            accepts=[],
            master_data_element_id=None,
        )
        self.backend.publish_app(
            self.alice,
            self.group["group_id"],
            self.editor["app_id"],
            1,
        )

        self.player = hosted_upload.create_uploaded_app(
            self.backend,
            self.alice,
            self.group["group_id"],
            "Alice Quiz Player",
            player_zip("player-v1"),
        )
        self.backend.register_authoring_contract(
            self.alice,
            self.group["group_id"],
            self.player["app_id"],
            edits=[],
            accepts=[FORMAT],
            master_data_element_id="quiz-master-data",
        )
        self.backend.publish_app(
            self.alice,
            self.group["group_id"],
            self.player["app_id"],
            1,
        )

    def _editor_index(self, launch: dict[str, object]) -> str:
        token = str(launch["content_path"]).split("/")[3]
        data, content_type = hosted_authoring_launch.get_editor_file(
            self.publisher,
            token,
            "index.html",
        )
        self.assertEqual(content_type, "text/html; charset=utf-8")
        return data.decode("utf-8")

    def _preview_index(self, preview: dict[str, object]) -> str:
        token = str(preview["content_path"]).split("/")[3]
        data, content_type = hosted_authoring_preview.get_preview_file(
            self.publisher,
            token,
            "index.html",
        )
        self.assertEqual(content_type, "text/html; charset=utf-8")
        return data.decode("utf-8")

    def test_bob_can_use_alices_published_editor_and_player_for_full_quiz_roundtrip(self) -> None:
        contracts = self.backend.list_authoring_apps(self.bob, self.group["group_id"])
        self.assertEqual(
            {item["app_id"] for item in contracts},
            {self.editor["app_id"], self.player["app_id"]},
        )

        project = self.backend.create_authoring_project(
            self.bob,
            self.group["group_id"],
            FORMAT,
            {},
        )
        self.assertEqual(project["draft_revision"], 1)

        launch = hosted_authoring_launch.create_launch(
            self.publisher,
            self.bob,
            project["content_id"],
            self.editor["app_id"],
        )
        self.assertIn("editor-v1", self._editor_index(launch))
        self.assertEqual(launch["content_format"], FORMAT)
        self.assertIn("save_document", launch["allowed_operations"])
        self.assertIn("publish_request", launch["allowed_operations"])

        saved = self.backend.save_authoring_document(
            self.bob,
            project["content_id"],
            expected_revision=1,
            document={
                "question": "2 + 2 = ?",
                "choices": [3, 4, 5],
                "answer": 4,
            },
        )
        self.assertEqual(saved["draft_revision"], 2)

        preview = hosted_authoring_preview.create_preview(
            self.publisher,
            self.bob,
            project["content_id"],
            self.player["app_id"],
            expected_revision=2,
        )
        preview_html = self._preview_index(preview)
        self.assertIn("player-v1", preview_html)
        self.assertIn('"question":"2 + 2 = ?"', preview_html)
        self.assertIn('"answer":4', preview_html)

        published = self.publisher.publish_authoring_project(
            self.bob,
            project["content_id"],
            expected_revision=2,
        )
        self.assertEqual(published["published_version"], 1)
        self.assertEqual(published["source_revision"], 2)

        reloaded = self.backend.load_authoring_project(self.bob, project["content_id"])
        self.assertEqual(reloaded["draft_revision"], 2)
        self.assertEqual(reloaded["document"]["answer"], 4)
        edited_again = self.backend.save_authoring_document(
            self.bob,
            project["content_id"],
            expected_revision=2,
            document={
                "question": "3 + 3 = ?",
                "choices": [5, 6, 7],
                "answer": 6,
            },
        )
        self.assertEqual(edited_again["draft_revision"], 3)

    def test_unpublished_editor_draft_never_leaks_and_live_session_stays_pinned(self) -> None:
        project = self.backend.create_authoring_project(
            self.bob,
            self.group["group_id"],
            FORMAT,
            {},
        )
        first_launch = hosted_authoring_launch.create_launch(
            self.publisher,
            self.bob,
            project["content_id"],
            self.editor["app_id"],
        )
        self.assertIn("editor-v1", self._editor_index(first_launch))

        updated = self.backend.update_editable_source(
            self.alice,
            self.group["group_id"],
            self.editor["app_id"],
            1,
            editor_zip("editor-v2-DRAFT"),
        )
        self.assertEqual(updated["revision"], 2)

        before_publish = hosted_authoring_launch.create_launch(
            self.publisher,
            self.bob,
            project["content_id"],
            self.editor["app_id"],
        )
        self.assertIn("editor-v1", self._editor_index(before_publish))
        self.assertNotIn("editor-v2-DRAFT", self._editor_index(before_publish))

        self.backend.publish_app(
            self.alice,
            self.group["group_id"],
            self.editor["app_id"],
            2,
        )
        after_publish = hosted_authoring_launch.create_launch(
            self.publisher,
            self.bob,
            project["content_id"],
            self.editor["app_id"],
        )
        self.assertIn("editor-v2-DRAFT", self._editor_index(after_publish))
        self.assertIn("editor-v1", self._editor_index(first_launch))

    def test_unpublished_player_draft_never_leaks_and_live_preview_stays_pinned(self) -> None:
        project = self.backend.create_authoring_project(
            self.bob,
            self.group["group_id"],
            FORMAT,
            {"question": "Pinned?", "answer": True},
        )
        first_preview = hosted_authoring_preview.create_preview(
            self.publisher,
            self.bob,
            project["content_id"],
            self.player["app_id"],
            expected_revision=1,
        )
        self.assertIn("player-v1", self._preview_index(first_preview))

        updated = self.backend.update_editable_source(
            self.alice,
            self.group["group_id"],
            self.player["app_id"],
            1,
            player_zip("player-v2-DRAFT"),
        )
        self.assertEqual(updated["revision"], 2)
        before_publish = hosted_authoring_preview.create_preview(
            self.publisher,
            self.bob,
            project["content_id"],
            self.player["app_id"],
            expected_revision=1,
        )
        self.assertIn("player-v1", self._preview_index(before_publish))

        self.backend.publish_app(
            self.alice,
            self.group["group_id"],
            self.player["app_id"],
            2,
        )
        after_publish = hosted_authoring_preview.create_preview(
            self.publisher,
            self.bob,
            project["content_id"],
            self.player["app_id"],
            expected_revision=1,
        )
        self.assertIn("player-v2-DRAFT", self._preview_index(after_publish))
        self.assertIn("player-v1", self._preview_index(first_preview))


if __name__ == "__main__":
    unittest.main()
