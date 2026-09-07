from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def write(rel: str, text: str) -> None:
    (ROOT / rel).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# 1) Canonical app-management authorization must also be reusable by short-lived
# capability validation, where only the bound user_id is available.
path = "backend/src/hosted_catalog_backend.py"
text = read(path)
old = '''    def _require_app_management_access(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        *,
        editable: bool,
    ) -> tuple[Any, dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        membership = self._require_active_membership(user.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        if (
            _item_string(app, "owner_user_id") != user.user_id
            and _item_string(membership, "role") != "owner"
        ):
            raise ApiProblem(403, "forbidden", "このアプリを管理する権限がありません。")
        if editable:
            self._require_editable_app(app)
        return user, app

'''
new = '''    def _require_app_management_access_for_user(
        self,
        user_id: str,
        group_id: str,
        app_id: str,
        *,
        editable: bool,
    ) -> dict[str, Any]:
        membership = self._require_active_membership(user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        if (
            _item_string(app, "owner_user_id") != user_id
            and _item_string(membership, "role") != "owner"
        ):
            raise ApiProblem(403, "forbidden", "このアプリを管理する権限がありません。")
        if editable:
            self._require_editable_app(app)
        return app

    def _require_app_management_access(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        *,
        editable: bool,
    ) -> tuple[Any, dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        app = self._require_app_management_access_for_user(
            user.user_id,
            group_id,
            app_id,
            editable=editable,
        )
        return user, app

'''
text = replace_once(text, old, new, "canonical management helper")
write(path, text)


# 2) Managed-app API: "my apps" remains author-only; group management gets an
# explicit management path. Preview file reads revalidate through the canonical
# backend contract instead of duplicating authorization.
path = "backend/src/hosted_app_management.py"
text = read(path)
text = replace_once(text, "import secrets\n", "", "remove redundant preview token generator")
old = '''def _owned_editable_app(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> tuple[Any, dict[str, Any]]:
    user = backend._user_by_auth_subject(auth_subject)
    app = backend._get_item(pk=f"APP#{app_id}", sk="META")
    if app is None:
        raise ApiProblem(404, "app_not_found", "指定されたアプリはありません。")
    if app.get("editable", {}).get("BOOL") is not True:
        raise ApiProblem(409, "app_not_manageable", "このアプリはマイアプリから管理できません。")
    if _item_string(app, "owner_user_id") != user.user_id:
        raise ApiProblem(403, "forbidden", "このアプリを管理する権限がありません。")
    group_id = _item_string(app, "group_id")
    backend._require_active_membership(user.user_id, group_id)
    if _optional_string(app, "deletion_state") is not None:
        raise ApiProblem(409, "app_deleting", "このアプリは削除処理中です。")
    return user, app

'''
new = '''def _author_editable_app(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> tuple[Any, dict[str, Any]]:
    app = backend._get_item(pk=f"APP#{app_id}", sk="META")
    if app is None:
        raise ApiProblem(404, "app_not_found", "指定されたアプリはありません。")
    group_id = _item_string(app, "group_id")
    return backend._require_app_author_access(
        auth_subject,
        group_id,
        app_id,
        editable=True,
    )

'''
text = replace_once(text, old, new, "author-only managed app helper")
text = replace_once(
    text,
    "    _, app = _owned_editable_app(backend, auth_subject, app_id)\n",
    "    _, app = _author_editable_app(backend, auth_subject, app_id)\n",
    "managed app detail author check",
)
old = '''def set_visibility(
    backend: Any,
    auth_subject: str,
    app_id: str,
    *,
    hidden: bool,
) -> dict[str, Any]:
    _, app = _owned_editable_app(backend, auth_subject, app_id)
    group_id = _item_string(app, "group_id")
    updated_at = _now_iso()
'''
new = '''def _set_visibility_authorized(
    backend: Any,
    app: dict[str, Any],
    *,
    hidden: bool,
) -> dict[str, Any]:
    app_id = _item_string(app, "app_id")
    group_id = _item_string(app, "group_id")
    updated_at = _now_iso()
'''
text = replace_once(text, old, new, "visibility authorized primitive")
marker = '''    if refreshed is None:
        raise RuntimeError("Managed app disappeared after visibility update")
    return _managed_payload(backend, refreshed)


def create_preview_session(
'''
replacement = '''    if refreshed is None:
        raise RuntimeError("Managed app disappeared after visibility update")
    return _managed_payload(backend, refreshed)


def set_visibility(
    backend: Any,
    auth_subject: str,
    app_id: str,
    *,
    hidden: bool,
) -> dict[str, Any]:
    _, app = _author_editable_app(backend, auth_subject, app_id)
    return _set_visibility_authorized(backend, app, hidden=hidden)


def set_group_visibility(
    backend: Any,
    auth_subject: str,
    group_id: str,
    app_id: str,
    *,
    hidden: bool,
) -> dict[str, Any]:
    _, app = backend._require_app_management_access(
        auth_subject,
        group_id,
        app_id,
        editable=True,
    )
    return _set_visibility_authorized(backend, app, hidden=hidden)


def create_preview_session(
'''
text = replace_once(text, marker, replacement, "public visibility paths")
start = text.index("def create_preview_session(\n")
end = text.index("def get_preview_file(\n", start)
text = text[:start] + text[end:]
old = '''    user_id = _item_string(session, "user_id")
    group_id = _item_string(session, "group_id")
    app_id = _item_string(session, "app_id")
    backend._require_active_membership(user_id, group_id)
    app = backend._require_app_in_group(app_id, group_id)
    if app.get("editable", {}).get("BOOL") is not True:
        raise ApiProblem(409, "app_not_manageable", "このアプリはプレビューできません。")
    if _item_string(app, "owner_user_id") != user_id:
        raise ApiProblem(403, "forbidden", "このアプリをプレビューする権限がありません。")
    if _optional_string(app, "deletion_state") is not None:
        raise ApiProblem(409, "app_deleting", "このアプリは削除処理中です。")

'''
new = '''    user_id = _item_string(session, "user_id")
    group_id = _item_string(session, "group_id")
    app_id = _item_string(session, "app_id")
    backend._require_app_management_access_for_user(
        user_id,
        group_id,
        app_id,
        editable=True,
    )

'''
text = replace_once(text, old, new, "preview capability reauthorization")
if "_owned_editable_app" in text or "def create_preview_session(" in text:
    raise RuntimeError("legacy managed preview path remains")
write(path, text)


# 3) Preview creation has two explicit callers: author-owned "my apps" and group
# management. Both mint the exact same pinned content/runtime capabilities after
# their own explicit authorization check.
write(
    "backend/src/hosted_preview_session.py",
    '''from __future__ import annotations

import hashlib
import secrets
import time
from typing import Any

from aws_backend import _item_string, _string_attr
from hosted_app_management import (
    PREVIEW_SESSION_SECONDS,
    PREVIEW_TTL_GRACE_SECONDS,
    _author_editable_app,
)
from hosted_catalog_backend import _files_json
from hosted_platform_backend import RUNTIME_SESSION_TTL_SECONDS, _number_attr


def _create_preview_session_for_authorized_app(
    backend: Any,
    user: Any,
    app: dict[str, Any],
    app_id: str,
) -> dict[str, Any]:
    group_id = _item_string(app, "group_id")
    source_revision = backend._source_revision(app)

    # Validate the immutable draft object before issuing either capability.
    _, files, sha256 = backend._read_current_source(app)
    source_key = _item_string(app, "source_key")

    content_token = secrets.token_urlsafe(32)
    content_token_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
    runtime_token = secrets.token_urlsafe(32)
    runtime_token_hash = hashlib.sha256(runtime_token.encode("ascii")).hexdigest()
    preview_state_id = secrets.token_hex(32)

    now_epoch = int(time.time())
    content_expires_at = now_epoch + PREVIEW_SESSION_SECONDS
    runtime_expires_at = now_epoch + RUNTIME_SESSION_TTL_SECONDS
    preview_state_ttl_epoch = (
        max(content_expires_at, runtime_expires_at) + PREVIEW_TTL_GRACE_SECONDS
    )

    content_session = {
        "pk": _string_attr(f"HOSTEDPREVIEW#{content_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("hosted_preview_session"),
        "user_id": _string_attr(user.user_id),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(app_id),
        "source_revision": _number_attr(source_revision),
        "source_key": _string_attr(source_key),
        "source_sha256": _string_attr(sha256),
        "source_files_json": _string_attr(_files_json(files)),
        "expires_at_epoch": _number_attr(content_expires_at),
        "ttl_epoch": _number_attr(content_expires_at + PREVIEW_TTL_GRACE_SECONDS),
    }
    runtime_session = {
        "pk": _string_attr(f"RUNTIMESESSION#{runtime_token_hash}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("runtime_session"),
        "group_id": _string_attr(group_id),
        "app_id": _string_attr(app_id),
        "user_id": _string_attr(user.user_id),
        "expires_at_epoch": _number_attr(runtime_expires_at),
        "ttl_epoch": _number_attr(runtime_expires_at + PREVIEW_TTL_GRACE_SECONDS),
        "preview_state_id": _string_attr(preview_state_id),
        "preview_state_ttl_epoch": _number_attr(preview_state_ttl_epoch),
    }

    # Content and Runtime capabilities are all-or-nothing. A failure must not
    # leave a preview URL whose state token was never created.
    backend._transact_put_new([content_session, runtime_session])

    return {
        "app_id": app_id,
        "group_id": group_id,
        "source_revision": source_revision,
        "content_path": f"/hosted/preview/{content_token}/index.html",
        "expires_in": PREVIEW_SESSION_SECONDS,
        "runtime_token": runtime_token,
        "runtime_expires_in": RUNTIME_SESSION_TTL_SECONDS,
    }


def create_author_preview_session(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> dict[str, Any]:
    user, app = _author_editable_app(backend, auth_subject, app_id)
    return _create_preview_session_for_authorized_app(backend, user, app, app_id)


def create_group_preview_session(
    backend: Any,
    auth_subject: str,
    group_id: str,
    app_id: str,
) -> dict[str, Any]:
    user, app = backend._require_app_management_access(
        auth_subject,
        group_id,
        app_id,
        editable=True,
    )
    return _create_preview_session_for_authorized_app(backend, user, app, app_id)
''',
)


# 4) Expose explicit group-management visibility/preview routes without changing
# the author-only semantics of /hosted/my/apps.
path = "backend/src/hosted_entry.py"
text = read(path)
old = '''_GROUP_APP_UPLOAD_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/upload$")
_MY_APP_RE = re.compile(rf"^/hosted/my/apps/{_ID_RE}$")
'''
new = '''_GROUP_APP_UPLOAD_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/upload$")
_GROUP_APP_VISIBILITY_RE = re.compile(
    rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/visibility$"
)
_GROUP_APP_PREVIEW_SESSION_RE = re.compile(
    rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/preview-session$"
)
_MY_APP_RE = re.compile(rf"^/hosted/my/apps/{_ID_RE}$")
'''
text = replace_once(text, old, new, "group management route regexes")
old = '''    thumbnail_match = _MY_APP_THUMBNAIL_RE.fullmatch(path)
'''
new = '''    group_visibility_match = _GROUP_APP_VISIBILITY_RE.fullmatch(path)
    if method == "POST" and group_visibility_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required={"hidden"})
        hidden = payload["hidden"]
        if not isinstance(hidden, bool):
            raise ApiProblem(400, "invalid_request", "hidden must be a boolean.")
        auth_subject = _auth_subject(event)
        backend = _get_backend()
        group_id, app_id = group_visibility_match.groups()
        return _json_response(
            200,
            hosted_app_management.set_group_visibility(
                backend,
                auth_subject,
                group_id,
                app_id,
                hidden=hidden,
            ),
        )

    thumbnail_match = _MY_APP_THUMBNAIL_RE.fullmatch(path)
'''
text = replace_once(text, old, new, "group visibility handler")
old = '''            hosted_preview_session.create_preview_session(
                backend,
                auth_subject,
                preview_match.group(1),
            ),
        )
    return None
'''
new = '''            hosted_preview_session.create_author_preview_session(
                backend,
                auth_subject,
                preview_match.group(1),
            ),
        )

    group_preview_match = _GROUP_APP_PREVIEW_SESSION_RE.fullmatch(path)
    if method == "POST" and group_preview_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required=set())
        auth_subject = _auth_subject(event)
        backend = _get_backend()
        group_id, app_id = group_preview_match.groups()
        return _json_response(
            201,
            hosted_preview_session.create_group_preview_session(
                backend,
                auth_subject,
                group_id,
                app_id,
            ),
        )
    return None
'''
text = replace_once(text, old, new, "explicit author/group preview routes")
write(path, text)


# 5) Deploy the two new authenticated group-management routes through the same
# Hosted identity Lambda. Public preview content remains capability-only.
path = "infra/hosted/app_management_routes.tf"
text = read(path)
old = '''    "POST /hosted/my/apps/{app_id}/visibility",
  ])
'''
new = '''    "POST /hosted/my/apps/{app_id}/visibility",
    "POST /hosted/groups/{group_id}/apps/{app_id}/preview-session",
    "POST /hosted/groups/{group_id}/apps/{app_id}/visibility",
  ])
'''
text = replace_once(text, old, new, "group management API Gateway routes")
write(path, text)


# 6) Update focused preview session unit test for the explicit author API.
path = "backend/tests/test_hosted_preview_session.py"
text = read(path)
text = replace_once(text, '"_owned_editable_app",', '"_author_editable_app",', "preview helper patch")
text = replace_once(
    text,
    "            result = hosted_preview_session.create_preview_session(\n",
    "            result = hosted_preview_session.create_author_preview_session(\n",
    "author preview function name",
)
write(path, text)


# 7) Entry tests verify both explicit preview paths and group visibility routing.
path = "backend/tests/test_hosted_preview_entry.py"
text = read(path)
text = text.replace("test_owner_preview_session_requires_empty_body_and_authenticated_subject", "test_author_preview_session_requires_empty_body_and_authenticated_subject")
text = text.replace("test_owner_preview_session_rejects_unknown_body_fields", "test_author_preview_session_rejects_unknown_body_fields")
text = replace_once(text, '"create_preview_session",\n            return_value=expected,', '"create_author_preview_session",\n            return_value=expected,', "author preview mock")
text = replace_once(text, '"create_preview_session",\n        ) as create:', '"create_author_preview_session",\n        ) as create:', "author preview reject mock")
insert = '''
    def test_group_management_preview_session_binds_group_and_app(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        expected = {
            "app_id": app_id,
            "group_id": group_id,
            "source_revision": 4,
            "content_path": "/hosted/preview/" + "A" * 43 + "/index.html",
            "expires_in": 600,
            "runtime_token": "B" * 43,
            "runtime_expires_in": 600,
        }
        with patch.object(
            hosted_entry.hosted_preview_session,
            "create_group_preview_session",
            return_value=expected,
        ) as create:
            response = hosted_entry.lambda_handler(
                event(
                    "POST",
                    f"/hosted/groups/{group_id}/apps/{app_id}/preview-session",
                    body={},
                    auth=True,
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"]), expected)
        create.assert_called_once_with(self.backend, "sub-owner", group_id, app_id)

    def test_group_management_visibility_binds_group_and_app(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        expected = {"app_id": app_id, "group_id": group_id, "visibility": "hidden"}
        with patch.object(
            hosted_entry.hosted_app_management,
            "set_group_visibility",
            return_value=expected,
        ) as set_visibility:
            response = hosted_entry.lambda_handler(
                event(
                    "POST",
                    f"/hosted/groups/{group_id}/apps/{app_id}/visibility",
                    body={"hidden": True},
                    auth=True,
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), expected)
        set_visibility.assert_called_once_with(
            self.backend,
            "sub-owner",
            group_id,
            app_id,
            hidden=True,
        )

'''
text = replace_once(text, "\n\nif __name__ == \"__main__\":\n", "\n" + insert + "\nif __name__ == \"__main__\":\n", "entry group route tests")
write(path, text)


# 8) End-to-end backend regression with real Hosted fakes: my-app identity stays
# author-only, group owner can manage/preview, unrelated members cannot, and an
# already-issued Preview is revoked by current authorization changes.
write(
    "backend/tests/test_hosted_managed_preview_authorization.py",
    '''from __future__ import annotations

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
            hidden=False,
        )
        self.assertEqual(visible["visibility"], "visible")
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
''',
)


# Final fail-fast guards for this issue's design boundary.
for rel in (
    "backend/src/hosted_app_management.py",
    "backend/src/hosted_preview_session.py",
):
    body = read(rel)
    if "_owned_editable_app" in body:
        raise RuntimeError(f"legacy owner-only preview helper remains in {rel}")
if "def create_preview_session(" in read("backend/src/hosted_app_management.py"):
    raise RuntimeError("duplicate legacy preview session implementation remains")

print("#173 managed-app / Preview authorization migration applied")
