from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
import hosted_app_management  # noqa: E402
from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
import hosted_upload  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3, source_zip  # noqa: E402


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

    def _join_bob(self) -> str:
        self.backend.register("bob", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        bob = self.cognito.users["bob"]["sub"]
        invite = self.backend.create_invite(self.subject, self.group["group_id"])
        self.backend.join_group(bob, invite["code"])
        return bob

    def _upload_editor(self) -> dict[str, object]:
        return hosted_upload.create_uploaded_app(
            self.backend,
            self.subject,
            self.group["group_id"],
            "Quiz Editor",
            source_zip("<!doctype html><h1>quiz-editor-v1</h1>"),
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

    def test_list_authoring_apps_returns_contracts_not_ordinary_apps(self) -> None:
        group_id = str(self.group["group_id"])
        editor = self.backend.install_builtin(self.subject, group_id, "novel-editor")
        player = self.backend.install_builtin(self.subject, group_id, "novel-starter")
        self.backend.install_builtin(self.subject, group_id, "shiba-game")

        apps = self.backend.list_authoring_apps(self.subject, group_id)

        self.assertEqual(
            {app["app_id"] for app in apps},
            {editor["app_id"], player["app_id"]},
        )
        editor_contract = next(app for app in apps if app["app_id"] == editor["app_id"])
        player_contract = next(app for app in apps if app["app_id"] == player["app_id"])
        self.assertEqual(
            editor_contract,
            {
                "app_id": editor["app_id"],
                "group_id": group_id,
                "title": "ノベルゲームメーカー",
                "edits": ["minapp/novel@1"],
                "accepts": [],
            },
        )
        self.assertEqual(
            player_contract,
            {
                "app_id": player["app_id"],
                "group_id": group_id,
                "title": "ひみつの放課後",
                "edits": [],
                "accepts": ["minapp/novel@1"],
            },
        )

    def test_third_party_contract_is_hidden_until_published_then_visible_to_member(self) -> None:
        uploaded = self._upload_editor()
        group_id = str(self.group["group_id"])
        app_id = str(uploaded["app_id"])
        contract = self.backend.register_authoring_contract(
            self.subject,
            group_id,
            app_id,
            edits=["example/quiz@1"],
            accepts=[],
            master_data_element_id=None,
        )
        self.assertEqual(contract["edits"], ["example/quiz@1"])
        self.assertEqual(self.backend.list_authoring_apps(self.subject, group_id), [])

        self.backend.publish_app(self.subject, group_id, app_id, 1)
        bob = self._join_bob()
        apps = self.backend.list_authoring_apps(bob, group_id)
        self.assertEqual(
            apps,
            [
                {
                    "app_id": app_id,
                    "group_id": group_id,
                    "title": "Quiz Editor",
                    "edits": ["example/quiz@1"],
                    "accepts": [],
                }
            ],
        )

    def test_hidden_third_party_authoring_app_is_not_discoverable(self) -> None:
        uploaded = self._upload_editor()
        group_id = str(self.group["group_id"])
        app_id = str(uploaded["app_id"])
        self.backend.register_authoring_contract(
            self.subject,
            group_id,
            app_id,
            edits=["example/quiz@1"],
            accepts=[],
            master_data_element_id=None,
        )
        self.backend.publish_app(self.subject, group_id, app_id, 1)
        hosted_app_management.set_visibility(
            self.backend,
            self.subject,
            app_id,
            hidden=True,
        )
        self.assertEqual(self.backend.list_authoring_apps(self.subject, group_id), [])

    def test_non_owner_cannot_register_contract_for_another_users_app(self) -> None:
        uploaded = self._upload_editor()
        bob = self._join_bob()
        with self.assertRaises(ApiProblem) as caught:
            self.backend.register_authoring_contract(
                bob,
                self.group["group_id"],
                str(uploaded["app_id"]),
                edits=["example/quiz@1"],
                accepts=[],
                master_data_element_id=None,
            )
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_player_contract_requires_explicit_master_data_target(self) -> None:
        uploaded = self._upload_editor()
        with self.assertRaises(ApiProblem) as caught:
            self.backend.register_authoring_contract(
                self.subject,
                self.group["group_id"],
                str(uploaded["app_id"]),
                edits=[],
                accepts=["example/quiz@1"],
                master_data_element_id=None,
            )
        self.assertEqual(caught.exception.status_code, 400)
        self.assertEqual(caught.exception.error, "invalid_authoring_contract")

    def test_contract_rejects_duplicate_or_unversioned_formats(self) -> None:
        uploaded = self._upload_editor()
        for edits in (["example/quiz@1", "example/quiz@1"], ["not-versioned"]):
            with self.subTest(edits=edits):
                with self.assertRaises(ApiProblem):
                    self.backend.register_authoring_contract(
                        self.subject,
                        self.group["group_id"],
                        str(uploaded["app_id"]),
                        edits=edits,
                        accepts=[],
                        master_data_element_id=None,
                    )

    def test_corrupt_authoring_app_contract_fails_instead_of_disappearing(self) -> None:
        group_id = str(self.group["group_id"])
        editor = self.backend.install_builtin(self.subject, group_id, "novel-editor")
        index = self.metadata.items[(f"GROUP#{group_id}", f"APP#{editor['app_id']}")]
        index["edits_json"] = _string_attr('["not-versioned"]')

        with self.assertRaisesRegex(RuntimeError, "invalid edits content format"):
            self.backend.list_authoring_apps(self.subject, group_id)

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

    def test_list_can_filter_by_explicit_content_format(self) -> None:
        novel = self._create("作品A")
        quiz = self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "example/quiz@1",
            {"content_format": "example/quiz@1", "schema_version": 1},
        )

        projects = self.backend.list_authoring_projects(
            self.subject,
            str(self.group["group_id"]),
            "minapp/novel@1",
        )

        self.assertEqual([project["content_id"] for project in projects], [novel["content_id"]])
        self.assertNotEqual(novel["content_id"], quiz["content_id"])

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
