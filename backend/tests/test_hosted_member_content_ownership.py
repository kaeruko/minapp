from __future__ import annotations

import io
import pathlib
import sys
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from errors import ApiProblem  # noqa: E402
import hosted_authoring_preview  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_publish_backend import (  # noqa: E402
    PublishFakeDynamoDb,
    PublishFakeS3,
)
from test_hosted_backend import FakeCognito  # noqa: E402


def player_source_zip() -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><script id='minapp-novel-story' type='application/json'>{}</script>",
        )
    return output.getvalue()


class HostedMemberContentOwnershipTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = PublishFakeDynamoDb()
        self.runtime = PublishFakeDynamoDb()
        self.s3 = PublishFakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-starter/v4/source.zip")
        ] = player_source_zip()
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
        self.group = self.indexed.create_group(self.alice, "共同制作部")
        invite = self.indexed.create_invite(self.alice, self.group["group_id"])
        self.indexed.join_group(self.bob, invite["code"])
        self.player = self.indexed.install_builtin(
            self.alice,
            self.group["group_id"],
            "novel-starter",
        )

    def test_active_member_can_create_edit_list_and_publish_own_content(self) -> None:
        created = self.indexed.create_authoring_project(
            self.bob,
            self.group["group_id"],
            "minapp/novel@1",
            {"schema_version": 1, "content_format": "minapp/novel@1", "title": "英単語"},
        )
        content_id = created["content_id"]

        bob_projects = self.indexed.list_authoring_projects(
            self.bob,
            self.group["group_id"],
        )
        self.assertEqual([project["content_id"] for project in bob_projects], [content_id])
        self.assertEqual(
            self.indexed.list_authoring_projects(self.alice, self.group["group_id"]),
            [],
        )

        saved = self.indexed.save_authoring_document(
            self.bob,
            content_id,
            expected_revision=1,
            document={
                "schema_version": 1,
                "content_format": "minapp/novel@1",
                "title": "英単語2",
            },
        )
        self.assertEqual(saved["draft_revision"], 2)
        hosted_authoring_preview.create_preview(
            self.indexed,
            self.bob,
            content_id,
            self.player["app_id"],
            expected_revision=2,
        )

        published = self.publisher.publish_authoring_project(
            self.bob,
            content_id,
            expected_revision=2,
        )
        self.assertEqual(published["source_revision"], 2)
        self.assertRegex(published["published_app_id"], r"^[0-9a-f]{32}$")

    def test_group_owner_cannot_edit_or_publish_another_members_content(self) -> None:
        created = self.indexed.create_authoring_project(
            self.bob,
            self.group["group_id"],
            "minapp/novel@1",
            {"schema_version": 1, "content_format": "minapp/novel@1"},
        )
        content_id = created["content_id"]

        with self.assertRaises(ApiProblem) as load_error:
            self.indexed.load_authoring_project(self.alice, content_id)
        self.assertEqual(load_error.exception.status_code, 403)
        self.assertEqual(load_error.exception.error, "forbidden")

        with self.assertRaises(ApiProblem) as publish_error:
            self.publisher.publish_authoring_project(
                self.alice,
                content_id,
                expected_revision=1,
            )
        self.assertEqual(publish_error.exception.status_code, 403)
        self.assertEqual(publish_error.exception.error, "forbidden")


if __name__ == "__main__":
    unittest.main()
