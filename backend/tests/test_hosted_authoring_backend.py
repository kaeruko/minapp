from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_authoring_backend import HostedAuthoringBackend  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito, FakeDynamoDb  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class AuthoringFakeDynamoDb(FakeDynamoDb):
    def __init__(self) -> None:
        super().__init__()
        self.force_authoring_conflict = False

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        authoring_update = next(
            (
                operation["Update"]
                for operation in TransactItems
                if "Update" in operation
                and "draft_revision = :expected_revision"
                in operation["Update"].get("ConditionExpression", "")
            ),
            None,
        )
        if authoring_update is None:
            super().transact_write_items(TransactItems=TransactItems)
            return

        if self.force_authoring_conflict:
            self.force_authoring_conflict = False
            raise FakeAwsError("TransactionCanceledException")

        key = (
            self._s(authoring_update["Key"]["pk"]),
            self._s(authoring_update["Key"]["sk"]),
        )
        current = self.items.get(key)
        if current is None:
            raise FakeAwsError("TransactionCanceledException")
        values = authoring_update["ExpressionAttributeValues"]
        if current.get("draft_revision") != values[":expected_revision"]:
            raise FakeAwsError("TransactionCanceledException")
        if "deletion_state" in current:
            raise FakeAwsError("TransactionCanceledException")

        for operation in TransactItems:
            if "Put" not in operation:
                continue
            request = operation["Put"]
            item = request["Item"]
            item_key = (self._s(item["pk"]), self._s(item["sk"]))
            if request.get("ConditionExpression") == "attribute_not_exists(pk)" and item_key in self.items:
                raise FakeAwsError("TransactionCanceledException")

        replacement = dict(current)
        names = authoring_update.get("ExpressionAttributeNames", {})
        assignments = authoring_update["UpdateExpression"].removeprefix("SET ").split(", ")
        for assignment in assignments:
            field, value_name = assignment.split(" = ", 1)
            replacement[names.get(field, field)] = values[value_name]
        self.items[key] = replacement

        for operation in TransactItems:
            if "Put" in operation:
                item = operation["Put"]["Item"]
                item_key = (self._s(item["pk"]), self._s(item["sk"]))
                self.items[item_key] = item


class HostedAuthoringBackendTests(unittest.TestCase):
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
        self.backend.register("alice", "secret12", "2026-08-28", "2026-08-28")
        self.subject = self.cognito.users["alice"]["sub"]
        self.group = self.backend.create_group(self.subject, "ノベル制作部")

    def _create(self) -> dict[str, Any]:
        return self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {
                "version": 1,
                "start": "scene_001",
                "scenes": {"scene_001": {"text": "こんにちは", "end": True}},
            },
        )

    def test_create_and_load_use_structured_objects_not_zip(self) -> None:
        created = self._create()
        content_id = created["content_id"]

        self.assertEqual(created["draft_revision"], 1)
        self.assertEqual(created["content_format"], "minapp/novel@1")
        self.assertEqual(created["assets"], [])
        self.assertIn((f"CONTENT#{content_id}", "META"), self.metadata.items)
        self.assertIn((f"CONTENT#{content_id}", "REVISION#000001"), self.metadata.items)

        object_keys = [key for bucket, key in self.s3.objects if bucket == "uploads"]
        self.assertEqual(len(object_keys), 1)
        self.assertTrue(object_keys[0].endswith("/revisions/000001/document.json"))
        self.assertFalse(any(key.endswith(".zip") for key in object_keys))

        loaded = self.backend.load_authoring_project(self.subject, content_id)
        self.assertEqual(loaded["draft_revision"], 1)
        self.assertEqual(loaded["document"]["start"], "scene_001")
        self.assertEqual(loaded["document"]["scenes"]["scene_001"]["text"], "こんにちは")

    def test_document_and_asset_changes_advance_immutable_revisions(self) -> None:
        created = self._create()
        content_id = created["content_id"]

        saved_document = self.backend.save_authoring_document(
            self.subject,
            content_id,
            expected_revision=1,
            document={
                "version": 1,
                "start": "scene_001",
                "scenes": {"scene_001": {"text": "こんばんは", "end": True}},
            },
        )
        self.assertEqual(saved_document["draft_revision"], 2)

        saved_asset = self.backend.save_authoring_asset(
            self.subject,
            content_id,
            expected_revision=2,
            path="audio/bgm.ogg",
            data=b"OggS-preview-audio",
        )
        self.assertEqual(saved_asset["draft_revision"], 3)
        self.assertEqual(saved_asset["assets"][0]["path"], "audio/bgm.ogg")
        self.assertEqual(saved_asset["assets"][0]["content_type"], "audio/ogg")

        asset_data, content_type = self.backend.get_authoring_asset(
            self.subject,
            content_id,
            "audio/bgm.ogg",
        )
        self.assertEqual(asset_data, b"OggS-preview-audio")
        self.assertEqual(content_type, "audio/ogg")

        deleted = self.backend.delete_authoring_asset(
            self.subject,
            content_id,
            expected_revision=3,
            path="audio/bgm.ogg",
        )
        self.assertEqual(deleted["draft_revision"], 4)
        self.assertEqual(deleted["assets"], [])

        for revision in range(1, 5):
            self.assertIn(
                (f"CONTENT#{content_id}", f"REVISION#{revision:06d}"),
                self.metadata.items,
            )
        object_keys = [key for bucket, key in self.s3.objects if bucket == "uploads"]
        self.assertTrue(any("revisions/000001/document.json" in key for key in object_keys))
        self.assertTrue(any("revisions/000002/document.json" in key for key in object_keys))
        self.assertTrue(any("revisions/000003/assets/audio/bgm.ogg" in key for key in object_keys))

    def test_stale_revision_fails_without_writing_alternate_state(self) -> None:
        created = self._create()
        content_id = created["content_id"]
        self.backend.save_authoring_document(
            self.subject,
            content_id,
            expected_revision=1,
            document={"version": 1, "start": "end", "scenes": {"end": {"end": True}}},
        )

        before_objects = dict(self.s3.objects)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.save_authoring_document(
                self.subject,
                content_id,
                expected_revision=1,
                document={"version": 1, "start": "stale", "scenes": {}},
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "revision_conflict")
        self.assertEqual(self.s3.objects, before_objects)
        self.assertEqual(
            self.backend.load_authoring_project(self.subject, content_id)["draft_revision"],
            2,
        )

    def test_racing_commit_conflict_cleans_new_immutable_object(self) -> None:
        created = self._create()
        content_id = created["content_id"]
        before_keys = set(self.s3.objects)
        self.metadata.force_authoring_conflict = True

        with self.assertRaises(ApiProblem) as caught:
            self.backend.save_authoring_document(
                self.subject,
                content_id,
                expected_revision=1,
                document={"version": 1, "start": "racing", "scenes": {}},
            )
        self.assertEqual(caught.exception.error, "revision_conflict")
        self.assertEqual(set(self.s3.objects), before_keys)
        self.assertNotIn((f"CONTENT#{content_id}", "REVISION#000002"), self.metadata.items)

    def test_validation_and_quotas_fail_closed(self) -> None:
        with self.assertRaises(ApiProblem) as bad_format:
            self.backend.create_authoring_project(
                self.subject,
                self.group["group_id"],
                "novel-v1",
                {"version": 1},
            )
        self.assertEqual(bad_format.exception.error, "invalid_content_format")

        with self.assertRaises(ApiProblem) as bad_json:
            self.backend.create_authoring_project(
                self.subject,
                self.group["group_id"],
                "minapp/novel@1",
                {"bad": float("nan")},
            )
        self.assertEqual(bad_json.exception.error, "invalid_master_data")

        created = self._create()
        content_id = created["content_id"]
        with self.assertRaises(ApiProblem) as traversal:
            self.backend.save_authoring_asset(
                self.subject,
                content_id,
                expected_revision=1,
                path="../secret.png",
                data=b"png",
            )
        self.assertEqual(traversal.exception.error, "invalid_authoring_asset_path")

        with self.assertRaises(ApiProblem) as executable:
            self.backend.save_authoring_asset(
                self.subject,
                content_id,
                expected_revision=1,
                path="run.exe",
                data=b"no",
            )
        self.assertEqual(executable.exception.error, "unsupported_authoring_asset_type")

        with patch("hosted_authoring_backend.MAX_AUTHORING_ASSET_BYTES", 3):
            with self.assertRaises(ApiProblem) as too_large:
                self.backend.save_authoring_asset(
                    self.subject,
                    content_id,
                    expected_revision=1,
                    path="images/a.png",
                    data=b"1234",
                )
        self.assertEqual(too_large.exception.error, "authoring_asset_too_large")


if __name__ == "__main__":
    unittest.main()
