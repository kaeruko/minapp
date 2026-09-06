from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _string_attr  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


class HostedAuthoringIndexedBackendTests(unittest.TestCase):
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
        self.group = self.backend.create_group(self.subject, "ノベル制作部")

    def _create(self, title: str) -> dict[str, object]:
        return self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {
                "schema_version": 1,
                "content_format": "minapp/novel@1",
                "content_revision": 1,
                "title": title,
                "start_scene_id": "scene-1",
                "scenes": [
                    {
                        "id": "scene-1",
                        "events": [{"id": "event-1", "type": "end", "label": "END"}],
                    }
                ],
            },
        )

    def test_create_writes_group_index_in_same_metadata_transaction(self) -> None:
        created = self._create("作品A")
        content_id = str(created["content_id"])
        group_id = str(self.group["group_id"])

        self.assertIn((f"CONTENT#{content_id}", "META"), self.metadata.items)
        self.assertIn((f"CONTENT#{content_id}", "REVISION#000001"), self.metadata.items)
        self.assertIn((f"GROUP#{group_id}", f"CONTENT#{content_id}"), self.metadata.items)

        index = self.metadata.items[(f"GROUP#{group_id}", f"CONTENT#{content_id}")]
        self.assertEqual(index["entity"], {"S": "authoring_content_index"})
        self.assertEqual(index["content_format"], {"S": "minapp/novel@1"})

    def test_list_uses_group_index_and_returns_public_project_metadata(self) -> None:
        first = self._create("作品A")
        second = self._create("作品B")

        projects = self.backend.list_authoring_projects(
            self.subject,
            str(self.group["group_id"]),
        )

        self.assertEqual({project["content_id"] for project in projects}, {first["content_id"], second["content_id"]})
        for project in projects:
            self.assertEqual(project["group_id"], self.group["group_id"])
            self.assertEqual(project["content_format"], "minapp/novel@1")
            self.assertEqual(project["status"], "draft")
            self.assertNotIn("document", project)

    def test_corrupt_group_index_fails_instead_of_skipping_project(self) -> None:
        created = self._create("作品A")
        content_id = str(created["content_id"])
        group_id = str(self.group["group_id"])
        index = self.metadata.items[(f"GROUP#{group_id}", f"CONTENT#{content_id}")]
        index["content_format"] = _string_attr("example/other@1")

        with self.assertRaisesRegex(RuntimeError, "format no longer matches"):
            self.backend.list_authoring_projects(self.subject, group_id)


if __name__ == "__main__":
    unittest.main()
