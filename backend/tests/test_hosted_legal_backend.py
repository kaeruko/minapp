from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_catalog_backend import BUILTIN_TEMPLATES  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_legal_backend import HostedLegalBackend  # noqa: E402
from test_hosted_catalog_backend import FakeS3, source_zip  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402


class HostedLegalBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-starter/v4/source.zip")
        ] = source_zip("<!doctype html><h1>novel-v4</h1>")
        self.backend = HostedLegalBackend(
            cognito=self.cognito,
            dynamodb=self.dynamo,
            runtime_dynamodb=self.dynamo,
            s3=self.s3,
            user_pool_id="pool",
            app_client_id="client",
            table_name="table",
            runtime_table_name="runtime-table",
            upload_bucket="uploads",
            published_bucket="published",
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(
            login_id,
            "secret12",
            TERMS_VERSION,
            PRIVACY_VERSION,
        )
        return self.cognito.users[login_id]["sub"]

    def test_hosted_catalog_adds_novel_without_mutating_core_catalog(self) -> None:
        core_before = {
            builtin_id: dict(template)
            for builtin_id, template in BUILTIN_TEMPLATES.items()
        }

        builtins = self.backend.list_builtin_templates()

        self.assertEqual(
            {item["builtin_id"] for item in builtins},
            {"shiba-game", "shiba-goshujin", "novel-starter", "novel-editor"},
        )
        novel = next(
            item for item in builtins if item["builtin_id"] == "novel-starter"
        )
        editor = next(
            item for item in builtins if item["builtin_id"] == "novel-editor"
        )
        self.assertEqual(novel["title"], "ひみつの放課後")
        self.assertEqual(novel["version"], 4)
        self.assertEqual(editor["title"], "ノベルゲームメーカー")
        self.assertEqual(editor["version"], 1)
        for item in (novel, editor):
            self.assertNotIn("source_key", item)
            self.assertNotIn("accepts", item)
            self.assertNotIn("edits", item)
        self.assertEqual(BUILTIN_TEMPLATES, core_before)
        self.assertNotIn("novel-starter", BUILTIN_TEMPLATES)
        self.assertNotIn("novel-editor", BUILTIN_TEMPLATES)

    def test_owner_can_install_and_fork_novel_starter_source(self) -> None:
        subject = self._register("novel-owner")
        group = self.backend.create_group(subject, "物語部")

        installed = self.backend.install_builtin(
            subject,
            group["group_id"],
            "novel-starter",
        )
        self.assertEqual(installed["builtin_id"], "novel-starter")
        self.assertEqual(installed["builtin_version"], 4)
        self.assertFalse(installed["editable"])

        forked = self.backend.fork_app(
            subject,
            group["group_id"],
            installed["app_id"],
            "わたしの物語",
        )
        self.assertEqual(forked["builtin_id"], "novel-starter")
        self.assertEqual(forked["builtin_version"], 4)
        self.assertEqual(forked["source_revision"], 1)
        self.assertTrue(forked["editable"])

        source_bytes, metadata = self.backend.get_editable_source(
            subject,
            group["group_id"],
            forked["app_id"],
        )
        with zipfile.ZipFile(io.BytesIO(source_bytes)) as archive:
            self.assertEqual(
                archive.read("index.html"),
                b"<!doctype html><h1>novel-v4</h1>",
            )
        self.assertEqual(metadata["revision"], 1)

    def test_active_member_can_install_builtin_as_its_author(self) -> None:
        alice = self._register("install-owner")
        bob = self._register("install-member")
        group = self.backend.create_group(alice, "インストール部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])

        installed = self.backend.install_builtin(
            bob,
            group["group_id"],
            "shiba-game",
        )
        bob_user = self.backend._user_by_auth_subject(bob)
        self.assertEqual(installed["owner_user_id"], bob_user.user_id)
        app_item = self.dynamo.items[(f"APP#{installed['app_id']}", "META")]
        self.assertEqual(app_item["owner_user_id"]["S"], bob_user.user_id)

    def test_author_and_group_owner_manage_app_but_other_members_cannot(self) -> None:
        alice = self._register("alice-owner")
        bob = self._register("bob-author")
        carol = self._register("carol-member")
        dave = self._register("dave-outsider")
        group = self.backend.create_group(alice, "共同制作部")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])
        self.backend.join_group(carol, invite["code"])
        installed = self.backend.install_builtin(
            alice,
            group["group_id"],
            "novel-starter",
        )

        bob_fork = self.backend.fork_app(
            bob,
            group["group_id"],
            installed["app_id"],
            "ぼぶの物語",
        )
        app_id = bob_fork["app_id"]
        bob_user = self.backend._user_by_auth_subject(bob)
        self.assertEqual(bob_fork["owner_user_id"], bob_user.user_id)
        app_item = self.dynamo.items[(f"APP#{app_id}", "META")]
        self.assertEqual(app_item["owner_user_id"]["S"], bob_user.user_id)

        member_v2 = source_zip("<!doctype html><h1>member-v2</h1>")
        updated = self.backend.update_editable_source(
            bob,
            group["group_id"],
            app_id,
            1,
            member_v2,
        )
        self.assertEqual(updated["revision"], 2)
        published = self.backend.publish_app(
            bob,
            group["group_id"],
            app_id,
            2,
        )
        self.assertEqual(published["published_version"], 1)

        _, owner_read = self.backend.get_editable_source(
            alice,
            group["group_id"],
            app_id,
        )
        self.assertEqual(owner_read["revision"], 2)
        owner_v3 = source_zip("<!doctype html><h1>owner-v3</h1>")
        owner_updated = self.backend.update_editable_source(
            alice,
            group["group_id"],
            app_id,
            2,
            owner_v3,
        )
        self.assertEqual(owner_updated["revision"], 3)
        owner_published = self.backend.publish_app(
            alice,
            group["group_id"],
            app_id,
            3,
        )
        self.assertEqual(owner_published["published_version"], 2)
        self.assertEqual(
            self.dynamo.items[(f"APP#{app_id}", "META")]["owner_user_id"]["S"],
            bob_user.user_id,
        )

        for operation in (
            lambda: self.backend.get_editable_source(carol, group["group_id"], app_id),
            lambda: self.backend.update_editable_source(
                carol,
                group["group_id"],
                app_id,
                3,
                owner_v3,
            ),
            lambda: self.backend.publish_app(carol, group["group_id"], app_id, 3),
            lambda: self.backend.delete_hosted_app(carol, group["group_id"], app_id),
            lambda: self.backend.get_editable_source(dave, group["group_id"], app_id),
            lambda: self.backend.fork_app(
                dave,
                group["group_id"],
                installed["app_id"],
                "outsider fork",
            ),
        ):
            with self.assertRaises(ApiProblem) as caught:
                operation()
            self.assertEqual(caught.exception.status_code, 403)
            self.assertEqual(caught.exception.error, "forbidden")

        self.backend.leave_group(bob, group["group_id"])
        self.assertIn((f"APP#{app_id}", "META"), self.dynamo.items)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.get_editable_source(bob, group["group_id"], app_id)
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

        self.backend.delete_hosted_app(alice, group["group_id"], app_id)
        self.assertNotIn((f"APP#{app_id}", "META"), self.dynamo.items)

    def test_registration_persists_versions_and_server_timestamp(self) -> None:
        result = self.backend.register(
            "alice",
            "secret12",
            TERMS_VERSION,
            PRIVACY_VERSION,
        )
        user_id = result["user_id"]
        subject = self.cognito.users["alice"]["sub"]

        user_item = self.dynamo.items[(f"USER#{user_id}", "PROFILE")]
        auth_item = self.dynamo.items[(f"AUTH#{subject}", "PROFILE")]
        for item in (user_item, auth_item):
            self.assertEqual(item["terms_version"]["S"], TERMS_VERSION)
            self.assertEqual(item["privacy_version"]["S"], PRIVACY_VERSION)
            self.assertIs(item["terms_accepted"]["BOOL"], True)
            self.assertIs(item["privacy_accepted"]["BOOL"], True)
            self.assertRegex(item["terms_accepted_at"]["S"], r"^\d{4}-\d{2}-\d{2}T")
            self.assertEqual(
                item["terms_accepted_at"]["S"],
                item["privacy_accepted_at"]["S"],
            )

        self.assertEqual(result["legal"]["terms_version"], TERMS_VERSION)
        self.assertEqual(result["legal"]["privacy_version"], PRIVACY_VERSION)
        self.assertEqual(result["legal"]["accepted_at"], user_item["terms_accepted_at"]["S"])
        self.assertIn("recovery_code", result)

    def test_backend_rejects_stale_versions_even_if_handler_is_bypassed(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            self.backend.register(
                "alice",
                "secret12",
                "stale-terms",
                PRIVACY_VERSION,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "terms_version_outdated")
        self.assertEqual(self.cognito.users, {})
        self.assertEqual(self.dynamo.items, {})


if __name__ == "__main__":
    unittest.main()
