from __future__ import annotations

from pathlib import Path
import re

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


def method_slice(text: str, name: str) -> tuple[int, int, str]:
    match = re.search(rf"^    def {re.escape(name)}\(", text, re.MULTILINE)
    if match is None:
        raise RuntimeError(f"method not found: {name}")
    start = match.start()
    next_match = re.search(r"^    def ", text[match.end():], re.MULTILINE)
    end = len(text) if next_match is None else match.end() + next_match.start()
    return start, end, text[start:end]


def replace_method(text: str, name: str, new_method: str) -> str:
    start, end, _ = method_slice(text, name)
    return text[:start] + new_method.rstrip() + "\n\n" + text[end:].lstrip("\n")


catalog_path = "backend/src/hosted_catalog_backend.py"
catalog = read(catalog_path)

helper = '''    def _require_app_management_access(
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
marker = "    def install_builtin(\n"
if "def _require_app_management_access(" in catalog:
    raise RuntimeError("catalog already contains app management helper")
if catalog.count(marker) != 1:
    raise RuntimeError("install_builtin marker count changed")
catalog = catalog.replace(marker, helper + marker, 1)

start, end, method = method_slice(catalog, "install_builtin")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n',
    '        creator = self._user_by_auth_subject(auth_subject)\n        self._require_active_membership(creator.user_id, group_id)\n',
    "catalog install authorization",
)
method = replace_once(
    method,
    '            "owner_user_id": _string_attr(owner.user_id),\n',
    '            "owner_user_id": _string_attr(creator.user_id),\n',
    "catalog install owner",
)
catalog = catalog[:start] + method + catalog[end:]

start, end, method = method_slice(catalog, "fork_app")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n',
    '        creator = self._user_by_auth_subject(auth_subject)\n        self._require_active_membership(creator.user_id, group_id)\n',
    "catalog fork authorization",
)
method = replace_once(
    method,
    '            "owner_user_id": _string_attr(owner.user_id),\n',
    '            "owner_user_id": _string_attr(creator.user_id),\n',
    "catalog fork owner",
)
catalog = catalog[:start] + method + catalog[end:]

start, end, method = method_slice(catalog, "get_editable_source")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n        app = self._require_app_in_group(app_id, group_id)\n        self._require_editable_app(app)\n',
    '        _, app = self._require_app_management_access(\n            auth_subject, group_id, app_id, editable=True\n        )\n',
    "catalog source get authorization",
)
catalog = catalog[:start] + method + catalog[end:]

start, end, method = method_slice(catalog, "update_editable_source")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n        app = self._require_app_in_group(app_id, group_id)\n        self._require_editable_app(app)\n',
    '        _, app = self._require_app_management_access(\n            auth_subject, group_id, app_id, editable=True\n        )\n',
    "catalog source update authorization",
)
catalog = catalog[:start] + method + catalog[end:]

start, end, method = method_slice(catalog, "publish_app")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n        app = self._require_app_in_group(app_id, group_id)\n        self._require_editable_app(app)\n',
    '        _, app = self._require_app_management_access(\n            auth_subject, group_id, app_id, editable=True\n        )\n',
    "catalog publish authorization",
)
catalog = catalog[:start] + method + catalog[end:]

start, end, method = method_slice(catalog, "delete_hosted_app")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n        self._require_app_in_group(app_id, group_id)\n',
    '        self._require_app_management_access(\n            auth_subject, group_id, app_id, editable=False\n        )\n',
    "catalog delete authorization",
)
catalog = catalog[:start] + method + catalog[end:]

catalog = replace_once(
    catalog,
    '            "group_id": _item_string(item, "group_id"),\n            "title": _item_string(item, "title"),\n',
    '            "group_id": _item_string(item, "group_id"),\n            "owner_user_id": _item_string(item, "owner_user_id"),\n            "title": _item_string(item, "title"),\n',
    "public app owner_user_id",
)

for method_name in (
    "install_builtin",
    "fork_app",
    "get_editable_source",
    "update_editable_source",
    "publish_app",
    "delete_hosted_app",
):
    _, _, method = method_slice(catalog, method_name)
    if "_require_owner_group" in method:
        raise RuntimeError(f"owner-only authorization remains in {method_name}")
write(catalog_path, catalog)


legal_path = "backend/src/hosted_legal_backend.py"
legal = read(legal_path)
legal = replace_once(
    legal,
    "from contextlib import contextmanager\nfrom contextvars import ContextVar\n",
    "",
    "legal context imports",
)
legal = replace_once(
    legal,
    "from typing import Any, Iterator\n",
    "from typing import Any\n",
    "legal Iterator import",
)
constant_start = legal.find("_APP_OWNER_GROUP_OVERRIDE:")
class_start = legal.find("\n\nclass HostedLegalBackend")
if constant_start < 0 or class_start < 0 or constant_start > class_start:
    raise RuntimeError("legal override constant block not found")
legal = legal[:constant_start] + legal[class_start + 2 :]

start = legal.find("    def _require_owner_group(")
end = legal.find("    def install_builtin(")
if start < 0 or end < 0 or start > end:
    raise RuntimeError("legal compatibility method block not found")
legal = legal[:start] + legal[end:]

start, end, method = method_slice(legal, "install_builtin")
method = replace_once(
    method,
    '        owner = self._user_by_auth_subject(auth_subject)\n        self._require_owner_group(owner.user_id, group_id)\n',
    '        creator = self._user_by_auth_subject(auth_subject)\n        self._require_active_membership(creator.user_id, group_id)\n',
    "legal install authorization",
)
method = replace_once(
    method,
    '            "owner_user_id": _string_attr(owner.user_id),\n',
    '            "owner_user_id": _string_attr(creator.user_id),\n',
    "legal install owner",
)
legal = legal[:start] + method + legal[end:]
for forbidden in ("_APP_OWNER_GROUP_OVERRIDE", "_allow_owned_app_group", "contextmanager", "ContextVar"):
    if forbidden in legal:
        raise RuntimeError(f"obsolete legal compatibility remains: {forbidden}")
write(legal_path, legal)


test_path = "backend/tests/test_hosted_legal_backend.py"
tests = read(test_path)
old_start = tests.find(
    "    def test_active_member_can_manage_own_app_but_group_owner_cannot_mutate_it(self) -> None:\n"
)
old_end = tests.find("    def test_registration_persists_versions_and_server_timestamp", old_start)
if old_start < 0 or old_end < 0:
    raise RuntimeError("old ownership regression test not found")
new_tests = '''    def test_active_member_can_install_builtin_as_its_author(self) -> None:
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

'''
tests = tests[:old_start] + new_tests + tests[old_end:]
write(test_path, tests)

# Final structural assertions: no Hosted app method may depend on group-owner-only
# authorization, and the production Legal backend must have no compatibility bypass.
legal = read(legal_path)
catalog = read(catalog_path)
if "_APP_OWNER_GROUP_OVERRIDE" in legal or "_allow_owned_app_group" in legal:
    raise RuntimeError("legacy owner override remains")
if '"owner_user_id": _item_string(item, "owner_user_id")' not in catalog:
    raise RuntimeError("public app contract still omits owner_user_id")

print("#172 source rewrite complete")
