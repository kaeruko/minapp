from __future__ import annotations

import copy
import re
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from rename_login_id import (  # noqa: E402
    _matching_user,
    _new_temporary_password,
    _replacement_items,
    _restore_transaction_items,
    _s,
    _transaction_items,
)


class RenameLoginIdTests(unittest.TestCase):
    def setUp(self) -> None:
        self.old_subject = "old-sub"
        self.new_subject = "new-sub"
        self.user_id = "a" * 32
        self.old_login_id = "student-12345678"
        self.new_login_id = "yamada"
        self.items = [
            {
                "pk": _s(f"AUTH#{self.old_subject}"),
                "sk": _s("PROFILE"),
                "entity": _s("auth_user"),
                "user_id": _s(self.user_id),
                "auth_subject": _s(self.old_subject),
                "login_id": _s(self.old_login_id),
                "role": _s("student"),
                "status": _s("active"),
            },
            {
                "pk": _s(f"USER#{self.user_id}"),
                "sk": _s("PROFILE"),
                "entity": _s("user"),
                "user_id": _s(self.user_id),
                "auth_subject": _s(self.old_subject),
                "login_id": _s(self.old_login_id),
                "role": _s("student"),
                "status": _s("active"),
            },
            {
                "pk": _s("GROUP#group"),
                "sk": _s(f"MEMBER#{self.user_id}"),
                "entity": _s("membership"),
                "user_id": _s(self.user_id),
                "login_id": _s(self.old_login_id),
                "role": _s("student"),
            },
            {
                "pk": _s("APP#app"),
                "sk": _s("META"),
                "entity": _s("app"),
                "owner_user_id": _s(self.user_id),
                "owner_login_id": _s(self.old_login_id),
            },
        ]

    def test_temporary_password_is_eight_easy_digits(self) -> None:
        for _ in range(100):
            password = _new_temporary_password()
            self.assertIsNotNone(re.fullmatch(r"[2-9]{8}", password))

    def test_matching_user_requires_exactly_one_profile(self) -> None:
        user = _matching_user(self.items, self.old_login_id)
        self.assertEqual(user["user_id"], _s(self.user_id))
        with self.assertRaisesRegex(RuntimeError, "found 0"):
            _matching_user(self.items, "suzuki")

    def test_replacement_preserves_user_id_and_updates_denormalized_login_ids(self) -> None:
        originals = copy.deepcopy(self.items)
        changed, old_auth, new_auth = _replacement_items(
            self.items,
            user_id=self.user_id,
            old_login_id=self.old_login_id,
            new_login_id=self.new_login_id,
            old_subject=self.old_subject,
            new_subject=self.new_subject,
        )

        self.assertEqual(self.items, originals, "helper must not mutate scanned source items")
        self.assertEqual(old_auth["pk"], _s(f"AUTH#{self.old_subject}"))
        self.assertEqual(new_auth["pk"], _s(f"AUTH#{self.new_subject}"))
        self.assertEqual(new_auth["login_id"], _s(self.new_login_id))

        user_profile = next(item for item in changed if item.get("entity") == _s("user"))
        self.assertEqual(user_profile["user_id"], _s(self.user_id))
        self.assertEqual(user_profile["auth_subject"], _s(self.new_subject))
        self.assertEqual(user_profile["login_id"], _s(self.new_login_id))

        membership = next(item for item in changed if item.get("entity") == _s("membership"))
        self.assertEqual(membership["login_id"], _s(self.new_login_id))

        app = next(item for item in changed if item.get("entity") == _s("app"))
        self.assertEqual(app["owner_login_id"], _s(self.new_login_id))

    def test_forward_and_restore_transactions_stay_atomic(self) -> None:
        changed, old_auth, new_auth = _replacement_items(
            self.items,
            user_id=self.user_id,
            old_login_id=self.old_login_id,
            new_login_id=self.new_login_id,
            old_subject=self.old_subject,
            new_subject=self.new_subject,
        )
        forward = _transaction_items(changed, table_name="table", old_auth_item=old_auth)
        self.assertEqual(len(forward), len(changed) + 1)
        self.assertIn("Delete", forward[0])

        restore = _restore_transaction_items(
            copy.deepcopy(self.items),
            table_name="table",
            new_auth_item=new_auth,
        )
        self.assertEqual(len(restore), len(self.items) + 1)
        self.assertIn("Delete", restore[0])


if __name__ == "__main__":
    unittest.main()
