from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_catalog_backend import HostedCatalogBackend  # noqa: E402
from test_hosted_backend import FakeAwsError, FakeCognito, FakeDynamoDb  # noqa: E402


def source_zip(index: str, **files: str) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", index)
        for name, value in files.items():
            archive.writestr(name, value)
    return output.getvalue()


class FakeS3:
    def __init__(self) -> None:
        self.objects: dict[tuple[str, str], bytes] = {}
        self.version_counter = 0

    def put_object(self, **request: Any) -> dict[str, Any]:
        key = (request["Bucket"], request["Key"])
        if request.get("IfNoneMatch") == "*" and key in self.objects:
            raise FakeAwsError("PreconditionFailed")
        body = request["Body"]
        if not isinstance(body, bytes):
            raise AssertionError("FakeS3 only accepts bytes")
        self.objects[key] = body
        self.version_counter += 1
        return {"VersionId": f"version-{self.version_counter}"}

    def get_object(self, *, Bucket: str, Key: str) -> dict[str, Any]:
        data = self.objects.get((Bucket, Key))
        if data is None:
            raise FakeAwsError("NoSuchKey")
        return {"Body": io.BytesIO(data)}

    def delete_object(
        self, *, Bucket: str, Key: str, VersionId: str | None = None
    ) -> dict[str, Any]:
        del VersionId
        self.objects.pop((Bucket, Key), None)
        return {}


class QuotaFakeDynamoDb(FakeDynamoDb):
    def update_item(
        self,
        *,
        TableName: str,
        Key: dict[str, dict[str, str]],
        UpdateExpression: str,
        ConditionExpression: str,
        ExpressionAttributeValues: dict[str, dict[str, str]],
    ) -> dict[str, Any]:
        del TableName
        if "request_count" not in UpdateExpression or "request_count" not in ConditionExpression:
            raise AssertionError((UpdateExpression, ConditionExpression))
        key = (self._s(Key["pk"]), self._s(Key["sk"]))
        item = self.items.get(key)
        if item is None:
            raise FakeAwsError("ConditionalCheckFailedException")
        current = int(item.get("request_count", {"N": "0"})["N"])
        limit = int(ExpressionAttributeValues[":limit"]["N"])
        if current >= limit:
            raise FakeAwsError("ConditionalCheckFailedException")
        replacement = dict(item)
        replacement["request_count"] = {"N": str(current + 1)}
        self.items[key] = replacement
        return {}


class HostedCatalogBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = QuotaFakeDynamoDb()
        self.runtime = QuotaFakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[("uploads", "hosted/templates/shiba-game/v1/source.zip")] = source_zip(
            "<h1>game-v1</h1>"
        )
        self.s3.objects[("uploads", "hosted/templates/shiba-goshujin/v1/source.zip")] = source_zip(
            "<h1>goshujin-v1</h1>"
        )
        self.backend = HostedCatalogBackend(
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

    def _register(self, login_id: str) -> str:
        self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"]

    def test_builtin_catalog_matches_mobile_builtin_ids(self) -> None:
        builtins = self.backend.list_builtin_templates()
        self.assertEqual(
            {item["builtin_id"] for item in builtins},
            {"shiba-game", "shiba-goshujin"},
        )
        self.assertTrue(all(item["version"] == 1 for item in builtins))
        self.assertTrue(all("source_key" not in item for item in builtins))

    def test_owner_can_install_fork_list_and_delete_builtin(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "月影荘")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-goshujin")
        self.assertEqual(installed["source_kind"], "builtin")
        self.assertFalse(installed["editable"])

        forked = self.backend.fork_app(
            alice,
            group["group_id"],
            installed["app_id"],
            "うちのごしゅじんどこわん",
        )
        self.assertEqual(forked["source_kind"], "fork")
        self.assertTrue(forked["editable"])
        self.assertEqual(forked["parent_app_id"], installed["app_id"])
        self.assertEqual(forked["builtin_id"], "shiba-goshujin")

        apps = self.backend.list_group_apps(alice, group["group_id"])
        self.assertEqual({app["app_id"] for app in apps}, {installed["app_id"], forked["app_id"]})

        self.backend.delete_hosted_app(alice, group["group_id"], forked["app_id"])
        remaining = self.backend.list_group_apps(alice, group["group_id"])
        self.assertEqual([app["app_id"] for app in remaining], [installed["app_id"]])

    def test_duplicate_builtin_install_is_rejected(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "秘密基地")
        self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        with self.assertRaises(ApiProblem) as caught:
            self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "builtin_already_installed")

    def test_member_can_list_but_cannot_install(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "創作部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])
        self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        self.assertEqual(len(self.backend.list_group_apps(bob, group["group_id"])), 1)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.install_builtin(bob, group["group_id"], "shiba-goshujin")
        self.assertEqual(caught.exception.status_code, 403)

    def test_app_count_guard_applies_to_forks(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "設定資料室")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        with patch("hosted_catalog_backend.MAX_APPS_PER_GROUP", 1):
            with self.assertRaises(ApiProblem) as caught:
                self.backend.fork_app(alice, group["group_id"], installed["app_id"], "fork")
        self.assertEqual(caught.exception.error, "app_limit_reached")

    def test_runtime_key_and_storage_quotas_are_enforced(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "小説部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])

        with patch("hosted_catalog_backend.MAX_RUNTIME_KEYS_PER_APP", 1):
            self.backend.set_runtime_state(session["token"], "chapter.one", {"x": 1})
            with self.assertRaises(ApiProblem) as caught:
                self.backend.set_runtime_state(session["token"], "chapter.two", {"x": 2})
        self.assertEqual(caught.exception.error, "runtime_key_limit_reached")

        with patch("hosted_catalog_backend.MAX_RUNTIME_BYTES_PER_APP", 10):
            with self.assertRaises(ApiProblem) as caught:
                self.backend.set_runtime_state(session["token"], "chapter.one", "0123456789")
        self.assertEqual(caught.exception.error, "runtime_storage_limit_reached")

    def test_runtime_session_request_budget_is_atomic_and_fail_closed(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "なりきり部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])

        with patch("hosted_catalog_backend.MAX_RUNTIME_REQUESTS_PER_SESSION", 2):
            for _ in range(2):
                with self.assertRaises(ApiProblem) as missing:
                    self.backend.get_runtime_state(session["token"], "missing")
                self.assertEqual(missing.exception.error, "state_not_found")
            with self.assertRaises(ApiProblem) as limited:
                self.backend.get_runtime_state(session["token"], "missing")
        self.assertEqual(limited.exception.status_code, 429)
        self.assertEqual(limited.exception.error, "runtime_request_limit_reached")

    def test_delete_app_removes_runtime_state(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "交換日記")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        session = self.backend.create_runtime_session(alice, group["group_id"], installed["app_id"])
        self.backend.set_runtime_state(session["token"], "diary.today", {"text": "わん"})
        self.assertTrue(self.runtime.items)
        self.backend.delete_hosted_app(alice, group["group_id"], installed["app_id"])
        self.assertFalse(self.runtime.items)

    def test_source_update_is_validated_and_rejects_stale_revision(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "編集部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        forked = self.backend.fork_app(alice, group["group_id"], installed["app_id"], "fork")

        initial, metadata = self.backend.get_editable_source(
            alice, group["group_id"], forked["app_id"]
        )
        self.assertEqual(metadata["revision"], 1)
        with zipfile.ZipFile(io.BytesIO(initial)) as archive:
            self.assertIn(b"game-v1", archive.read("index.html"))

        changed = source_zip("<h1>draft-v2</h1>", **{"assets/app.js": "console.log('ok')"})
        updated = self.backend.update_editable_source(
            alice, group["group_id"], forked["app_id"], 1, changed
        )
        self.assertEqual(updated["revision"], 2)
        self.assertEqual(updated["files"], ["assets/app.js", "index.html"])

        with self.assertRaises(ApiProblem) as stale:
            self.backend.update_editable_source(
                alice, group["group_id"], forked["app_id"], 1, changed
            )
        self.assertEqual(stale.exception.error, "source_revision_stale")

        with self.assertRaises(ApiProblem) as invalid:
            self.backend.update_editable_source(
                alice,
                group["group_id"],
                forked["app_id"],
                2,
                source_zip("ok", **{"../escape.js": "bad"}),
            )
        self.assertEqual(invalid.exception.error, "invalid_zip_path")

    def test_publish_is_immutable_and_active_member_can_read_without_aws_credentials(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "公開部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        forked = self.backend.fork_app(alice, group["group_id"], installed["app_id"], "fork")
        published = self.backend.publish_app(alice, group["group_id"], forked["app_id"], 1)
        self.assertEqual(published["published_version"], 1)

        self.backend.update_editable_source(
            alice,
            group["group_id"],
            forked["app_id"],
            1,
            source_zip("<h1>unpublished draft</h1>"),
        )
        session = self.backend.create_published_session(bob, group["group_id"], forked["app_id"])
        self.assertEqual(set(session), {"content_path", "published_version", "expires_in"})
        token = session["content_path"].split("/")[3]
        content, content_type = self.backend.get_published_file(token, "index.html")
        self.assertIn(b"game-v1", content)
        self.assertNotIn(b"unpublished", content)
        self.assertEqual(content_type, "text/html; charset=utf-8")

    def test_delete_fork_removes_manifested_draft_and_published_objects(self) -> None:
        alice = self._register("alice")
        group = self.backend.create_group(alice, "片付け部屋")
        installed = self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        forked = self.backend.fork_app(alice, group["group_id"], installed["app_id"], "fork")
        self.backend.publish_app(alice, group["group_id"], forked["app_id"], 1)

        app_id = forked["app_id"]
        app_objects = {
            key for key in self.s3.objects if f"/{app_id}/" in key[1]
        }
        self.assertEqual(len(app_objects), 2)
        self.backend.delete_hosted_app(alice, group["group_id"], app_id)
        self.assertFalse({key for key in self.s3.objects if f"/{app_id}/" in key[1]})
        self.assertFalse({key for key in self.metadata.items if key[0] == f"APP#{app_id}"})


if __name__ == "__main__":
    unittest.main()
