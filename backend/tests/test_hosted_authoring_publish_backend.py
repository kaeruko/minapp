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
import hosted_authoring_preview  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


def player_source_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><script id='minapp-novel-story' type='application/json'>{}</script>"
            "<script src='player.js'></script>",
        )
        archive.writestr("player.js", "window.playerLoaded = true;")
    return buffer.getvalue()


class PublishFakeDynamoDb(AuthoringFakeDynamoDb):
    def __init__(self) -> None:
        super().__init__()
        self.force_publish_conflict = False

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        publish_update = next(
            (
                operation["Update"]
                for operation in TransactItems
                if "Update" in operation
                and "published_version" in operation["Update"].get("UpdateExpression", "")
            ),
            None,
        )
        if publish_update is None:
            super().transact_write_items(TransactItems=TransactItems)
            return

        if self.force_publish_conflict:
            self.force_publish_conflict = False
            raise FakeAwsError("TransactionCanceledException")

        key = (
            self._s(publish_update["Key"]["pk"]),
            self._s(publish_update["Key"]["sk"]),
        )
        current = self.items.get(key)
        if current is None:
            raise FakeAwsError("TransactionCanceledException")
        values = publish_update["ExpressionAttributeValues"]
        if current.get("draft_revision") != values[":expected_revision"]:
            raise FakeAwsError("TransactionCanceledException")
        if "deletion_state" in current:
            raise FakeAwsError("TransactionCanceledException")
        if ":previous_version" in values:
            if current.get("published_version") != values[":previous_version"]:
                raise FakeAwsError("TransactionCanceledException")
        elif "published_version" in current:
            raise FakeAwsError("TransactionCanceledException")

        puts: list[dict[str, Any]] = []
        for operation in TransactItems:
            if "Put" not in operation:
                continue
            request = operation["Put"]
            item = request["Item"]
            item_key = (self._s(item["pk"]), self._s(item["sk"]))
            if request.get("ConditionExpression") == "attribute_not_exists(pk)" and item_key in self.items:
                raise FakeAwsError("TransactionCanceledException")
            puts.append(item)

        replacement = dict(current)
        assignments = publish_update["UpdateExpression"].removeprefix("SET ").split(", ")
        for assignment in assignments:
            field, value_name = assignment.split(" = ", 1)
            replacement[field] = values[value_name]
        self.items[key] = replacement
        for item in puts:
            self.items[(self._s(item["pk"]), self._s(item["sk"]))] = item


class PublishFakeS3(FakeS3):
    def __init__(self) -> None:
        super().__init__()
        self.corrupt_published_reads = False

    def get_object(self, *, Bucket: str, Key: str) -> dict[str, Any]:
        response = super().get_object(Bucket=Bucket, Key=Key)
        if Bucket == "published" and self.corrupt_published_reads:
            data = self.objects[(Bucket, Key)] + b"corrupt"
            return {"Body": io.BytesIO(data)}
        return response


class HostedAuthoringPublishBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = PublishFakeDynamoDb()
        self.runtime = PublishFakeDynamoDb()
        self.s3 = PublishFakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-starter/v4/source.zip")
        ] = player_source_zip()
        self.backend = HostedAuthoringPublishBackend(
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
        self.group = self.backend.create_group(self.subject, "公開テスト部")
        self.player = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-starter",
        )
        self.created = self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {
                "version": 1,
                "start": "scene_001",
                "scenes": {"scene_001": {"text": "公開前", "end": True}},
            },
        )
        self.content_id = self.created["content_id"]
        hosted_authoring_preview.create_preview(
            self.backend,
            self.subject,
            self.content_id,
            self.player["app_id"],
            expected_revision=1,
        )

    def test_publish_materializes_and_verifies_immutable_objects_before_pointer(self) -> None:
        with_asset = self.backend.save_authoring_asset(
            self.subject,
            self.content_id,
            expected_revision=1,
            path="audio/bgm.ogg",
            data=b"OggS-publish",
        )
        self.assertEqual(with_asset["draft_revision"], 2)

        published = self.backend.publish_authoring_project(
            self.subject,
            self.content_id,
            expected_revision=2,
        )

        self.assertEqual(published["published_version"], 1)
        self.assertEqual(published["source_revision"], 2)
        self.assertEqual(published["player_app_id"], self.player["app_id"])
        self.assertEqual(published["assets"][0]["path"], "audio/bgm.ogg")
        published_app_id = published["published_app_id"]
        self.assertRegex(published_app_id, r"^[0-9a-f]{32}$")
        meta = self.metadata.items[(f"CONTENT#{self.content_id}", "META")]
        self.assertEqual(meta["published_version"]["N"], "1")
        self.assertEqual(meta["published_revision"]["N"], "2")
        self.assertEqual(meta["published_app_id"]["S"], published_app_id)
        manifest = self.metadata.items[(f"CONTENT#{self.content_id}", "PUBLISHED#000001")]
        self.assertEqual(manifest["source_revision"]["N"], "2")
        self.assertEqual(manifest["published_app_id"]["S"], published_app_id)
        app = self.metadata.items[(f"APP#{published_app_id}", "META")]
        self.assertEqual(app["source_kind"]["S"], "authoring")
        self.assertEqual(app["published_version"]["N"], "1")
        published_keys = [key for bucket, key in self.s3.objects if bucket == "published"]
        self.assertTrue(any(key.endswith("/document.json") for key in published_keys))
        self.assertTrue(any(key.endswith("/assets/audio/bgm.ogg") for key in published_keys))
        self.assertTrue(any(key.endswith("/source.zip") for key in published_keys))

        launch = self.backend.create_published_session(
            self.subject,
            self.group["group_id"],
            published_app_id,
        )
        token = launch["content_path"].split("/")[3]
        index, content_type = self.backend.get_published_file(token, "index.html")
        self.assertEqual(content_type, "text/html; charset=utf-8")
        self.assertIn(b'"scene_001"', index)
        bgm, bgm_type = self.backend.get_published_file(token, "audio/bgm.ogg")
        self.assertEqual(bgm, b"OggS-publish")
        self.assertEqual(bgm_type, "audio/ogg")

    def test_same_draft_revision_is_not_silently_published_again(self) -> None:
        self.backend.publish_authoring_project(
            self.subject,
            self.content_id,
            expected_revision=1,
        )
        before = dict(self.s3.objects)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.publish_authoring_project(
                self.subject,
                self.content_id,
                expected_revision=1,
            )
        self.assertEqual(caught.exception.error, "draft_already_published")
        self.assertEqual(self.s3.objects, before)

    def test_new_draft_revision_reuses_same_published_app_id(self) -> None:
        first = self.backend.publish_authoring_project(
            self.subject,
            self.content_id,
            expected_revision=1,
        )
        self.assertEqual(first["published_version"], 1)
        saved = self.backend.save_authoring_document(
            self.subject,
            self.content_id,
            expected_revision=1,
            document={"version": 1, "start": "end", "scenes": {"end": {"text": "更新", "end": True}}},
        )
        second = self.backend.publish_authoring_project(
            self.subject,
            self.content_id,
            expected_revision=saved["draft_revision"],
        )
        self.assertEqual(second["published_version"], 2)
        self.assertEqual(second["published_app_id"], first["published_app_id"])
        self.assertIn((f"CONTENT#{self.content_id}", "PUBLISHED#000001"), self.metadata.items)
        self.assertIn((f"CONTENT#{self.content_id}", "PUBLISHED#000002"), self.metadata.items)
        app = self.metadata.items[(f"APP#{first['published_app_id']}", "META")]
        self.assertEqual(app["published_version"]["N"], "2")

    def test_publish_without_explicit_player_selection_fails(self) -> None:
        self.metadata.items.pop((f"CONTENT#{self.content_id}", "PLAYER"))
        before = dict(self.s3.objects)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.publish_authoring_project(
                self.subject,
                self.content_id,
                expected_revision=1,
            )
        self.assertEqual(caught.exception.error, "authoring_player_not_selected")
        self.assertEqual(self.s3.objects, before)

    def test_published_validation_failure_never_advances_pointer_and_cleans_objects(self) -> None:
        self.s3.corrupt_published_reads = True
        with self.assertRaises(RuntimeError):
            self.backend.publish_authoring_project(
                self.subject,
                self.content_id,
                expected_revision=1,
            )
        meta = self.metadata.items[(f"CONTENT#{self.content_id}", "META")]
        self.assertNotIn("published_version", meta)
        self.assertFalse(any(bucket == "published" for bucket, _ in self.s3.objects))
        self.assertNotIn((f"CONTENT#{self.content_id}", "PUBLISHED#000001"), self.metadata.items)

    def test_pointer_race_returns_conflict_and_cleans_uncommitted_objects(self) -> None:
        self.metadata.force_publish_conflict = True
        with self.assertRaises(ApiProblem) as caught:
            self.backend.publish_authoring_project(
                self.subject,
                self.content_id,
                expected_revision=1,
            )
        self.assertEqual(caught.exception.error, "publish_conflict")
        meta = self.metadata.items[(f"CONTENT#{self.content_id}", "META")]
        self.assertNotIn("published_version", meta)
        self.assertFalse(any(bucket == "published" for bucket, _ in self.s3.objects))


if __name__ == "__main__":
    unittest.main()
