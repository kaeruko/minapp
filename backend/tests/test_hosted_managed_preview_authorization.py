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
from hosted_app_management import (  # noqa: E402
    get_managed_app,
    get_preview_file,
    list_managed_apps,
    set_group_visibility,
    set_visibility,
)
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_legal_backend import HostedLegalBackend  # noqa: E402
from hosted_preview_session import (  # noqa: E402
    create_author_preview_session,
    create_group_preview_session,
)
from hosted_upload import create_uploaded_app  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402


def app_zip(label: str) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            f'<!doctype html><link rel="stylesheet" href="assets/app.css"><h1>{label}</h1>',
        )
        archive.writestr("assets/app.css", f"/* {label} */ body {{ margin: 0; }}")
    return buffer.getvalue()


class HostedManagedPreviewAuthorizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.s3 = FakeS3()
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
        self.alice = self._register("alice-owner")
        self.bob = self._register("bob-author")
        self.carol = self._register("carol-member")
        self.group = self.backend.create_group(self.alice, "共同制作部")
        self.group_id = self.group["group_id"]
        invite = self.backend.create_invite(self.alice, self.group_id)
        self.backend.join_group(self.bob, invite["code"])
        self.backend.join_group(self.carol, invite["code"])
        self.alice_app = create_uploaded_app(
            self.backend,
            self.alice,
            self.group_id,
            "alice app",
            app_zip("alice-v1"),
        )
        self.bob_app = create_uploaded_app(
            self.backend,
            self.bob,
            self.group_id,
            "bob app",
            app_zip("bob-v1"),
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(
            login_id,
            "secret12",
            TERMS_VERSION,
            PRIVACY_VERSION,
        )
        return self.cognito.users[login_id]["sub"]

    @staticmethod
    def _token(session: dict[str, object]) -> str:
        return str(session["content_path"]).split("/")[3]

    def test_my_apps_and_detail_are_author_only_even_for_group_owner(self) -> None:
        alice_apps = list_managed_apps(self.backend, self.alice)
        bob_apps = list_managed_apps(self.backend, self.bob)
        self.assertEqual([app["app_id"] for app in alice_apps], [self.alice_app["app_id"]])
        self.assertEqual([app["app_id"] for app in bob_apps], [self.bob_app["app_id"]])

        detail = get_managed_app(self.backend, self.bob, self.bob_app["app_id"])
        self.assertEqual(detail["owner_user_id"], self.bob_app["owner_user_id"])
        with self.assertRaises(ApiProblem) as caught:
            get_managed_app(self.backend, self.alice, self.bob_app["app_id"])
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_author_and_group_owner_can_change_visibility_but_other_member_cannot(self) -> None:
        hidden = set_visibility(
            self.backend,
            self.bob,
            self.bob_app["app_id"],
            hidden=True,
        )
        self.assertEqual(hidden["visibility"], "hidden")

        visible = set_group_visibility(
            self.backend,
            self.alice,
            self.group_id,
            self.bob_app["app_id"],
            hidden=True,
        )
        self.assertEqual(visible["visibility"], "hidden")
        self.assertEqual(visible["owner_user_id"], self.bob_app["owner_user_id"])

        with self.assertRaises(ApiProblem) as caught:
            set_group_visibility(
                self.backend,
                self.carol,
                self.group_id,
                self.bob_app["app_id"],
                hidden=True,
            )
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_author_and_group_owner_preview_index_and_assets_but_other_member_cannot(self) -> None:
        author_session = create_author_preview_session(
            self.backend,
            self.bob,
            self.bob_app["app_id"],
        )
        author_token = self._token(author_session)
        index, index_type = get_preview_file(self.backend, author_token, "index.html")
        css, css_type = get_preview_file(self.backend, author_token, "assets/app.css")
        self.assertIn(b"bob-v1", index)
        self.assertIn(b"bob-v1", css)
        self.assertEqual(index_type, "text/html; charset=utf-8")
        self.assertEqual(css_type, "text/css; charset=utf-8")

        owner_session = create_group_preview_session(
            self.backend,
            self.alice,
            self.group_id,
            self.bob_app["app_id"],
        )
        owner_token = self._token(owner_session)
        owner_index, _ = get_preview_file(self.backend, owner_token, "index.html")
        self.assertIn(b"bob-v1", owner_index)

        with self.assertRaises(ApiProblem) as caught:
            create_group_preview_session(
                self.backend,
                self.carol,
                self.group_id,
                self.bob_app["app_id"],
            )
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_preview_is_pinned_and_never_falls_forward_to_new_source_revision(self) -> None:
        session = create_author_preview_session(
            self.backend,
            self.bob,
            self.bob_app["app_id"],
        )
        self.backend.update_editable_source(
            self.bob,
            self.group_id,
            self.bob_app["app_id"],
            1,
            app_zip("bob-v2"),
        )
        pinned, _ = get_preview_file(self.backend, self._token(session), "index.html")
        self.assertIn(b"bob-v1", pinned)
        self.assertNotIn(b"bob-v2", pinned)
        self.assertEqual(session["source_revision"], 1)

    def test_author_membership_loss_revokes_already_issued_preview(self) -> None:
        session = create_author_preview_session(
            self.backend,
            self.bob,
            self.bob_app["app_id"],
        )
        self.backend.leave_group(self.bob, self.group_id)
        with self.assertRaises(ApiProblem) as caught:
            get_preview_file(self.backend, self._token(session), "index.html")
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_group_owner_role_loss_revokes_already_issued_preview(self) -> None:
        session = create_group_preview_session(
            self.backend,
            self.alice,
            self.group_id,
            self.bob_app["app_id"],
        )
        carol_user = self.backend._user_by_auth_subject(self.carol)
        self.backend.transfer_group_ownership(
            self.alice,
            self.group_id,
            carol_user.user_id,
        )
        with self.assertRaises(ApiProblem) as caught:
            get_preview_file(self.backend, self._token(session), "index.html")
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_deleted_app_invalidates_already_issued_preview(self) -> None:
        session = create_group_preview_session(
            self.backend,
            self.alice,
            self.group_id,
            self.bob_app["app_id"],
        )
        self.backend.delete_hosted_app(
            self.alice,
            self.group_id,
            self.bob_app["app_id"],
        )
        with self.assertRaises(ApiProblem) as caught:
            get_preview_file(self.backend, self._token(session), "index.html")
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "app_not_found")


if __name__ == "__main__":
    unittest.main()
