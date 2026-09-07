from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from aws_backend import _item_string, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_authoring_deletion import delete_authoring_project  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_platform_backend import _number_attr  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class DeletionFakeDynamoDb(AuthoringFakeDynamoDb):
    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        start_update = next(
            (
                operation["Update"]
                for operation in TransactItems
                if "Update" in operation
                and operation["Update"]["Key"]["pk"].get("S", "").startswith("CONTENT#")
                and "deletion_state = :deleting" in operation["Update"].get("UpdateExpression", "")
            ),
            None,
        )
        if start_update is not None:
            if len(TransactItems) != 2 or "Delete" not in TransactItems[1]:
                raise AssertionError(TransactItems)
            meta_key = (
                self._s(start_update["Key"]["pk"]),
                self._s(start_update["Key"]["sk"]),
            )
            current = self.items.get(meta_key)
            if current is None:
                raise FakeAwsError("TransactionCanceledException")
            values = start_update["ExpressionAttributeValues"]
            if current.get("status") != values[":draft"] or "deletion_state" in current:
                raise FakeAwsError("TransactionCanceledException")

            delete = TransactItems[1]["Delete"]
            index_key = (self._s(delete["Key"]["pk"]), self._s(delete["Key"]["sk"]))
            index = self.items.get(index_key)
            if index is None or index.get("owner_user_id") != delete["ExpressionAttributeValues"][":owner_user_id"]:
                raise FakeAwsError("TransactionCanceledException")

            replacement = dict(current)
            names = start_update.get("ExpressionAttributeNames", {})
            assignments = start_update["UpdateExpression"].removeprefix("SET ").split(", ")
            for assignment in assignments:
                field, value_name = assignment.split(" = ", 1)
                replacement[names.get(field, field)] = values[value_name]
            self.items[meta_key] = replacement
            self.items.pop(index_key, None)
            return

        if len(TransactItems) == 1 and "Put" in TransactItems[0]:
            request = TransactItems[0]["Put"]
            if request.get("ConditionExpression") == "deletion_state = :deleting":
                item = request["Item"]
                key = (self._s(item["pk"]), self._s(item["sk"]))
                current = self.items.get(key)
                expected = request["ExpressionAttributeValues"][":deleting"]
                if current is None or current.get("deletion_state") != expected:
                    raise FakeAwsError("TransactionCanceledException")
                self.items[key] = item
                return

        super().transact_write_items(TransactItems=TransactItems)


class VersionedFakeS3(FakeS3):
    def __init__(self) -> None:
        super().__init__()
        self.versions: dict[tuple[str, str], str] = {}
        self.metadata: dict[tuple[str, str], dict[str, str]] = {}
        self.fail_delete_key: tuple[str, str] | None = None
        self.failed_delete_once = False

    def put_object(self, **request: Any) -> dict[str, Any]:
        response = super().put_object(**request)
        key = (request["Bucket"], request["Key"])
        version_id = response.get("VersionId")
        if not isinstance(version_id, str) or not version_id:
            raise AssertionError(response)
        self.versions[key] = version_id
        raw_metadata = request.get("Metadata", {})
        if not isinstance(raw_metadata, dict):
            raise AssertionError(raw_metadata)
        self.metadata[key] = dict(raw_metadata)
        return response

    def head_object(self, *, Bucket: str, Key: str) -> dict[str, Any]:
        ref = (Bucket, Key)
        if ref not in self.objects:
            raise FakeAwsError("NoSuchKey")
        return {
            "VersionId": self.versions[ref],
            "Metadata": dict(self.metadata.get(ref, {})),
        }

    def delete_object(
        self,
        *,
        Bucket: str,
        Key: str,
        VersionId: str | None = None,
    ) -> dict[str, Any]:
        ref = (Bucket, Key)
        if (
            self.fail_delete_key == ref
            and not self.failed_delete_once
        ):
            self.failed_delete_once = True
            raise RuntimeError("simulated Authoring S3 cleanup failure")
        if VersionId is not None and ref in self.versions and self.versions[ref] != VersionId:
            raise AssertionError((ref, VersionId, self.versions[ref]))
        self.objects.pop(ref, None)
        self.versions.pop(ref, None)
        self.metadata.pop(ref, None)
        return {}


class HostedAuthoringDeletionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = DeletionFakeDynamoDb()
        self.runtime = DeletionFakeDynamoDb()
        self.s3 = VersionedFakeS3()
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
        self.user = self.backend._user_by_auth_subject(self.subject)
        self.group = self.backend.create_group(self.subject, "作品削除テスト")

    def _create(self) -> dict[str, Any]:
        return self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "example/quiz@1",
            {},
        )

    def test_unpublished_project_delete_removes_manifested_objects_and_is_idempotent(self) -> None:
        created = self._create()
        content_id = created["content_id"]
        self.backend.save_authoring_document(
            self.subject,
            content_id,
            expected_revision=1,
            document={"schema_version": 1, "questions": []},
        )
        self.backend.save_authoring_asset(
            self.subject,
            content_id,
            expected_revision=2,
            path="images/cover.png",
            data=b"png-data",
        )

        delete_authoring_project(self.backend, self.subject, content_id)

        tombstone = self.metadata.items[(f"CONTENT#{content_id}", "META")]
        self.assertEqual(_item_string(tombstone, "entity"), "authoring_content_tombstone")
        self.assertEqual(_item_string(tombstone, "status"), "deleted")
        self.assertEqual(_item_string(tombstone, "deletion_state"), "deleted")
        self.assertNotIn(
            (f"GROUP#{self.group['group_id']}", f"CONTENT#{content_id}"),
            self.metadata.items,
        )
        self.assertEqual(
            [key for key in self.metadata.items if key[0] == f"CONTENT#{content_id}"],
            [(f"CONTENT#{content_id}", "META")],
        )
        self.assertFalse(
            any(
                bucket == "uploads" and key.startswith("authoring/")
                for bucket, key in self.s3.objects
            )
        )
        self.assertEqual(
            self.backend.list_authoring_projects(
                self.subject,
                self.group["group_id"],
                "example/quiz@1",
            ),
            [],
        )

        delete_authoring_project(self.backend, self.subject, content_id)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.load_authoring_project(self.subject, content_id)
        self.assertEqual(caught.exception.error, "content_not_editable")

    def test_s3_cleanup_failure_keeps_deleting_state_and_retry_finishes(self) -> None:
        created = self._create()
        content_id = created["content_id"]
        authoring_keys = sorted(
            (bucket, key)
            for bucket, key in self.s3.objects
            if bucket == "uploads" and key.startswith("authoring/")
        )
        self.assertTrue(authoring_keys)
        self.s3.fail_delete_key = authoring_keys[0]

        with self.assertRaisesRegex(RuntimeError, "simulated Authoring S3 cleanup failure"):
            delete_authoring_project(self.backend, self.subject, content_id)

        deleting = self.metadata.items[(f"CONTENT#{content_id}", "META")]
        self.assertEqual(_item_string(deleting, "status"), "deleting")
        self.assertEqual(_item_string(deleting, "deletion_state"), "deleting")
        self.assertNotIn(
            (f"GROUP#{self.group['group_id']}", f"CONTENT#{content_id}"),
            self.metadata.items,
        )

        delete_authoring_project(self.backend, self.subject, content_id)
        tombstone = self.metadata.items[(f"CONTENT#{content_id}", "META")]
        self.assertEqual(_item_string(tombstone, "status"), "deleted")
        delete_authoring_project(self.backend, self.subject, content_id)

    def test_published_project_delete_removes_normal_app_and_authoring_publication(self) -> None:
        created = self._create()
        content_id = created["content_id"]
        group_id = self.group["group_id"]
        app_id = "a" * 32

        current = self.metadata.items[(f"CONTENT#{content_id}", "META")]
        current["published_app_id"] = _string_attr(app_id)
        current["published_version"] = _number_attr(1)
        current["published_revision"] = _number_attr(1)

        document_data = b"{}"
        document_sha = hashlib.sha256(document_data).hexdigest()
        document_key = f"published/{group_id}/{content_id}/versions/000001/document.json"
        self.s3.put_object(
            Bucket="published",
            Key=document_key,
            Body=document_data,
            ContentType="application/json; charset=utf-8",
            Metadata={"sha256": document_sha},
            IfNoneMatch="*",
        )
        self.metadata.items[(f"CONTENT#{content_id}", "PUBLISHED#000001")] = {
            "pk": _string_attr(f"CONTENT#{content_id}"),
            "sk": _string_attr("PUBLISHED#000001"),
            "entity": _string_attr("authoring_published_version"),
            "content_id": _string_attr(content_id),
            "group_id": _string_attr(group_id),
            "owner_user_id": _string_attr(self.user.user_id),
            "content_format": _string_attr("example/quiz@1"),
            "document_key": _string_attr(document_key),
            "document_sha256": _string_attr(document_sha),
            "assets_json": _string_attr("{}"),
        }

        artifact_data = b"published-app-zip"
        artifact_sha = hashlib.sha256(artifact_data).hexdigest()
        artifact_key = f"hosted/published/{group_id}/{app_id}/versions/000001/source.zip"
        artifact_put = self.s3.put_object(
            Bucket="published",
            Key=artifact_key,
            Body=artifact_data,
            ContentType="application/zip",
            Metadata={"sha256": artifact_sha},
            IfNoneMatch="*",
        )
        version_id = artifact_put["VersionId"]
        common = {
            "entity": _string_attr("app"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "owner_user_id": _string_attr(self.user.user_id),
            "source_kind": _string_attr("authoring"),
            "authoring_content_id": _string_attr(content_id),
            "editable": {"BOOL": False},
        }
        self.metadata.items[(f"APP#{app_id}", "META")] = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("META"),
            **common,
        }
        self.metadata.items[(f"GROUP#{group_id}", f"APP#{app_id}")] = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{app_id}"),
            **common,
        }
        self.metadata.items[(f"APP#{app_id}", "PUBLISHED#000001")] = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("PUBLISHED#000001"),
            "entity": _string_attr("hosted_published_version"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "published_key": _string_attr(artifact_key),
            "s3_version_id": _string_attr(version_id),
        }

        delete_authoring_project(self.backend, self.subject, content_id)

        self.assertNotIn((f"APP#{app_id}", "META"), self.metadata.items)
        self.assertNotIn((f"GROUP#{group_id}", f"APP#{app_id}"), self.metadata.items)
        self.assertFalse(any(key[0] == f"APP#{app_id}" for key in self.metadata.items))
        self.assertNotIn(("published", artifact_key), self.s3.objects)
        self.assertNotIn(("published", document_key), self.s3.objects)
        tombstone = self.metadata.items[(f"CONTENT#{content_id}", "META")]
        self.assertEqual(_item_string(tombstone, "status"), "deleted")


if __name__ == "__main__":
    unittest.main()
