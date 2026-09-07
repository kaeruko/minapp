from __future__ import annotations

import io
import pathlib
import sys
import unittest
import zipfile
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from errors import ApiProblem  # noqa: E402
import hosted_authoring_launch  # noqa: E402
import hosted_authoring_preview  # noqa: E402
import hosted_authoring_session  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
import hosted_upload  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class RoundTripDynamoDb(AuthoringFakeDynamoDb):
    def update_item(
        self,
        *,
        TableName: str,
        Key: dict[str, dict[str, str]],
        UpdateExpression: str,
        ConditionExpression: str,
        ExpressionAttributeValues: dict[str, dict[str, str]],
    ) -> dict[str, Any]:
        del TableName, UpdateExpression
        key = (self._s(Key["pk"]), self._s(Key["sk"]))
        item = self.items.get(key)
        if item is None:
            raise FakeAwsError("ConditionalCheckFailedException")
        current = int(item.get("request_count", {"N": "0"})["N"])
        limit = int(ExpressionAttributeValues[":limit"]["N"])
        if current >= limit:
            raise FakeAwsError("ConditionalCheckFailedException")
        if "expires_at_epoch > :now" in ConditionExpression:
            now = int(ExpressionAttributeValues[":now"]["N"])
            expires = int(item.get("expires_at_epoch", {"N": "0"})["N"])
            if expires <= now:
                raise FakeAwsError("ConditionalCheckFailedException")
        replacement = dict(item)
        replacement["request_count"] = {"N": str(current + 1)}
        self.items[key] = replacement
        return {}


def editor_zip(marker: str) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><script src='editor.js'></script>",
        )
        archive.writestr("editor.js", f"window.quizEditor = '{marker}';")
    return output.getvalue()


def player_zip(marker: str) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><main id='quiz'></main>"
            "<script id='quiz-data' type='application/json'>{}</script>"
            "<script src='player.js'></script>",
        )
        archive.writestr("player.js", f"window.quizPlayer = '{marker}';")
    return output.getvalue()


def quiz_document(question: str) -> dict[str, object]:
    return {
        "schema_version": 1,
        "content_format": "example/quiz@1",
        "questions": [
            {
                "id": "q1",
                "question": question,
                "choices": ["A", "B"],
                "answer": 0,
            }
        ],
    }


class HostedThirdPartyAuthoringRoundTripTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = RoundTripDynamoDb()
        self.runtime = RoundTripDynamoDb()
        self.s3 = FakeS3()
        kwargs = dict(
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
        self.indexed = HostedAuthoringIndexedBackend(**kwargs)
        self.publisher = HostedAuthoringPublishBackend(**kwargs)

        self.indexed.register("alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.indexed.register("bob", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.alice = self.cognito.users["alice"]["sub"]
        self.bob = self.cognito.users["bob"]["sub"]
        self.group = self.indexed.create_group(self.alice, "Quiz Lab")
        self.group_id = self.group["group_id"]
        invite = self.indexed.create_invite(self.alice, self.group_id)
        self.indexed.join_group(self.bob, invite["code"])

        self.editor = hosted_upload.create_uploaded_app(
            self.indexed,
            self.alice,
            self.group_id,
            "Alice Quiz Editor",
            editor_zip("published-v1"),
        )
        self.indexed.register_authoring_contract(
            self.alice,
            self.group_id,
            self.editor["app_id"],
            edits=["example/quiz@1"],
            accepts=[],
            master_data_element_id=None,
        )
        self.indexed.publish_app(
            self.alice,
            self.group_id,
            self.editor["app_id"],
            expected_revision=1,
        )
        # Alice can keep editing her Editor, but Bob must continue to receive
        # only the immutable version Alice actually published.
        updated_editor = self.indexed.update_editable_source(
            self.alice,
            self.group_id,
            self.editor["app_id"],
            expected_revision=1,
            zip_bytes=editor_zip("private-draft-v2"),
        )
        self.assertEqual(updated_editor["revision"], 2)

        self.player = hosted_upload.create_uploaded_app(
            self.indexed,
            self.alice,
            self.group_id,
            "Alice Quiz Player",
            player_zip("published-v1"),
        )
        self.indexed.register_authoring_contract(
            self.alice,
            self.group_id,
            self.player["app_id"],
            edits=[],
            accepts=["example/quiz@1"],
            master_data_element_id="quiz-data",
        )
        self.indexed.publish_app(
            self.alice,
            self.group_id,
            self.player["app_id"],
            expected_revision=1,
        )

    def test_alice_third_party_editor_and_player_can_build_bobs_normal_app(self) -> None:
        contracts = self.indexed.list_authoring_apps(self.bob, self.group_id)
        self.assertEqual(
            {item["app_id"] for item in contracts},
            {self.editor["app_id"], self.player["app_id"]},
        )

        project = self.indexed.create_authoring_project(
            self.bob,
            self.group_id,
            "example/quiz@1",
            {},
        )
        content_id = project["content_id"]
        loaded_initial = self.indexed.load_authoring_project(self.bob, content_id)
        self.assertEqual(loaded_initial["document"], {})

        launch = hosted_authoring_launch.create_launch(
            self.indexed,
            self.bob,
            content_id,
            self.editor["app_id"],
        )
        editor_token = launch["content_path"].split("/")[3]
        editor_js, _ = hosted_authoring_launch.get_editor_file(
            self.indexed,
            editor_token,
            "editor.js",
        )
        self.assertIn(b"published-v1", editor_js)
        self.assertNotIn(b"private-draft-v2", editor_js)

        capability_loaded = hosted_authoring_session.load_project(
            self.indexed,
            launch["authoring_token"],
        )
        self.assertEqual(capability_loaded["document"], {})
        saved = hosted_authoring_session.save_document(
            self.indexed,
            launch["authoring_token"],
            expected_revision=1,
            document=quiz_document("2 + 2 = ?"),
        )
        self.assertEqual(saved["draft_revision"], 2)

        preview = hosted_authoring_preview.create_preview(
            self.indexed,
            self.bob,
            content_id,
            self.player["app_id"],
            expected_revision=2,
        )
        preview_token = preview["content_path"].split("/")[3]
        preview_index, _ = hosted_authoring_preview.get_preview_file(
            self.indexed,
            preview_token,
            "index.html",
        )
        self.assertIn(b"2 + 2 = ?", preview_index)

        published = hosted_authoring_session.publish_project(
            self.publisher,
            launch["authoring_token"],
            expected_revision=2,
        )
        published_app_id = published["published_app_id"]
        self.assertEqual(published["player_app_id"], self.player["app_id"])
        self.assertEqual(published["player_source_version"], 1)

        normal_apps = self.publisher.list_group_apps(self.bob, self.group_id)
        work_apps = [app for app in normal_apps if app["app_id"] == published_app_id]
        self.assertEqual(len(work_apps), 1)
        self.assertEqual(work_apps[0]["source_kind"], "authoring")
        self.assertEqual(work_apps[0]["published_version"], 1)

        normal_launch = self.publisher.create_published_session(
            self.bob,
            self.group_id,
            published_app_id,
        )
        normal_token = normal_launch["content_path"].split("/")[3]
        normal_index, _ = self.publisher.get_published_file(
            normal_token,
            "index.html",
        )
        self.assertIn(b"2 + 2 = ?", normal_index)
        normal_player_js, _ = self.publisher.get_published_file(
            normal_token,
            "player.js",
        )
        self.assertIn(b"published-v1", normal_player_js)

        edited = hosted_authoring_session.save_document(
            self.indexed,
            launch["authoring_token"],
            expected_revision=2,
            document=quiz_document("3 + 3 = ?"),
        )
        self.assertEqual(edited["draft_revision"], 3)
        republished = hosted_authoring_session.publish_project(
            self.publisher,
            launch["authoring_token"],
            expected_revision=3,
        )
        self.assertEqual(republished["published_app_id"], published_app_id)
        self.assertEqual(republished["published_version"], 2)

        normal_apps_after = self.publisher.list_group_apps(self.bob, self.group_id)
        self.assertEqual(
            len([app for app in normal_apps_after if app["app_id"] == published_app_id]),
            1,
        )
        latest_launch = self.publisher.create_published_session(
            self.bob,
            self.group_id,
            published_app_id,
        )
        latest_token = latest_launch["content_path"].split("/")[3]
        latest_index, _ = self.publisher.get_published_file(
            latest_token,
            "index.html",
        )
        self.assertIn(b"3 + 3 = ?", latest_index)
        self.assertNotIn(b"2 + 2 = ?", latest_index)

    def test_member_never_gets_editor_source_management_rights(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            self.indexed.get_editable_source(
                self.bob,
                self.group_id,
                self.editor["app_id"],
            )
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")


if __name__ == "__main__":
    unittest.main()
