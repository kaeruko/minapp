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


# 1) Canonical backend: distinguish exact app authorship from app-management
# capability, and separate authorization from destructive cleanup so subclasses do
# not need a second authorization pass.
path = "backend/src/hosted_catalog_backend.py"
text = read(path)
management_helper = '''    def _require_app_management_access(
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
author_helper = '''    def _require_app_author_access(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        *,
        editable: bool,
    ) -> tuple[Any, dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        if _item_string(app, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "このアプリの作者ではありません。")
        if editable:
            self._require_editable_app(app)
        return user, app

'''
if "def _require_app_author_access(" in text:
    raise RuntimeError("author helper already exists")
text = replace_once(text, management_helper, management_helper + author_helper, "insert author helper")

old_delete_head = '''    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        self._require_app_management_access(
            auth_subject, group_id, app_id, editable=False
        )

        deleting_at = _now_iso()
'''
new_delete_head = '''    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        self._require_app_management_access(
            auth_subject, group_id, app_id, editable=False
        )
        self._delete_hosted_app_authorized(group_id, app_id)

    def _delete_hosted_app_authorized(self, group_id: str, app_id: str) -> None:
        deleting_at = _now_iso()
'''
text = replace_once(text, old_delete_head, new_delete_head, "split delete authorization")
write(path, text)

# 2) userState cleanup must authorize once, before touching private rows, then call
# the already-authorized destructive primitive. No old exact-owner helper and no
# duplicate authorization pass through super().
path = "backend/src/hosted_user_state_backend.py"
text = read(path)
old = '''        self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=False,
        )
        self._delete_all_runtime_user_state(group_id, app_id)
        super().delete_hosted_app(auth_subject, group_id, app_id)
'''
new = '''        self._require_app_management_access(
            auth_subject,
            group_id,
            app_id,
            editable=False,
        )
        self._delete_all_runtime_user_state(group_id, app_id)
        self._delete_hosted_app_authorized(group_id, app_id)
'''
text = replace_once(text, old, new, "userState app deletion authorization")
write(path, text)

# 3) Authoring contract registration is source-management, not group moderation.
# Preserve its explicit author-only rule using the semantic author helper.
path = "backend/src/hosted_authoring_indexed_backend.py"
text = read(path)
old = '''        user, _ = self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
'''
new = '''        user, _ = self._require_app_author_access(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
'''
text = replace_once(text, old, new, "Authoring contract author authorization")
write(path, text)

# 4) Core catalog regression must express the new creation rule rather than the
# old owner-only policy.
path = "backend/tests/test_hosted_catalog_backend.py"
text = read(path)
old = '''    def test_member_can_list_but_cannot_install(self) -> None:
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

'''
new = '''    def test_active_member_can_list_and_install_as_app_author(self) -> None:
        alice = self._register("alice")
        bob = self._register("bob")
        group = self.backend.create_group(alice, "創作部屋")
        invite = self.backend.create_invite(alice, group["group_id"])
        self.backend.join_group(bob, invite["code"])
        self.backend.install_builtin(alice, group["group_id"], "shiba-game")
        self.assertEqual(len(self.backend.list_group_apps(bob, group["group_id"])), 1)

        installed = self.backend.install_builtin(
            bob,
            group["group_id"],
            "shiba-goshujin",
        )
        bob_user = self.backend._user_by_auth_subject(bob)
        self.assertEqual(installed["owner_user_id"], bob_user.user_id)
        self.assertEqual(len(self.backend.list_group_apps(bob, group["group_id"])), 2)

'''
text = replace_once(text, old, new, "catalog member install regression")
write(path, text)

# Fail if the deleted compatibility helper still has a production caller.
for rel in (ROOT / "backend/src").glob("*.py"):
    body = rel.read_text(encoding="utf-8")
    if "_require_owned_app" in body:
        raise RuntimeError(f"legacy _require_owned_app remains in {rel.name}")

print("#172 remaining authorization migrations complete")
