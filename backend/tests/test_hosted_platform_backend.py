from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_platform_backend import HostedPlatformBackend  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402


class HostedPlatformBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = FakeDynamoDb()
        self.runtime = FakeDynamoDb()
        self.backend = HostedPlatformBackend(
            cognito=self.cognito,
            dynamodb=self.metadata,
            runtime_dynamodb=self.runtime,
            user_pool_id="pool",
            app_client_id="client",
            table_name="metadata",
            runtime_table_name="runtime",
        )

    def _register(self, login_id: str) -> tuple[str, str]:
        result = self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"], result["recovery_code"]

    def _join(self, owner_subject: str, member_subject: str, group_id: str) -> None:
        invite = self.backend.create_invite(owner_subject, group_id)
        self.backend.join_group(member_subject, invite["code"])

    def _seed_app(self, group_id: str, app_id: str) -> None:
        self.metadata.items[(f"APP#{app_id}", "META")] = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("app"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
        }
        self.metadata.items[(f"GROUP#{group_id}", f"APP#{app_id}#VERSION#{'1' * 32}")] = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{app_id}#VERSION#{'1' * 32}"),
            "entity": _string_attr("app_version"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
        }

    def _remove_seeded_app(self, group_id: str, app_id: str) -> None:
        del self.metadata.items[(f"APP#{app_id}", "META")]
        del self.metadata.items[(f"GROUP#{group_id}", f"APP#{app_id}#VERSION#{'1' * 32}")]

    def test_registration_returns_one_time_recovery_code_and_recovery_rotates_it(self) -> None:
        _, recovery_code = self._register("alice")
        self.assertGreaterEqual(len(recovery_code), 20)

        recovered = self.backend.recover_account("alice", recovery_code, "newsecret12")
        self.assertNotEqual(recovered["recovery_code"], recovery_code)
        logged_in = self.backend.login("alice", "newsecret12")
        self.assertEqual(logged_in["state"], "authenticated")

        with self.assertRaises(ApiProblem) as caught:
            self.backend.recover_account("alice", recovery_code, "thirdsecret12")
        self.assertEqual(caught.exception.status_code, 401)
        self.assertEqual(caught.exception.error, "invalid_recovery_credentials")

    def test_authenticated_user_can_rotate_recovery_code(self) -> None:
        alice, old_code = self._register("alice")
        rotated = self.backend.rotate_recovery_code(alice)
        self.assertNotEqual(rotated["recovery_code"], old_code)

        with self.assertRaises(ApiProblem) as caught:
            self.backend.recover_account("alice", old_code, "newsecret12")
        self.assertEqual(caught.exception.error, "invalid_recovery_credentials")

    def test_owner_can_transfer_ownership_and_old_owner_can_then_delete_account(self) -> None:
        alice, _ = self._register("alice")
        bob, _ = self._register("bob")
        group = self.backend.create_group(alice, "月影荘")
        self._join(alice, bob, group["group_id"])
        bob_id = self.backend.me(bob)["user"]["user_id"]

        transferred = self.backend.transfer_group_ownership(alice, group["group_id"], bob_id)
        self.assertEqual(transferred["owner_user_id"], bob_id)
        roles = {member["login_id"]: member["role"] for member in self.backend.list_members(bob, group["group_id"])}
        self.assertEqual(roles, {"alice": "member", "bob": "owner"})

        self.backend.delete_account(alice)
        self.assertNotIn("alice", self.cognito.users)
        self.assertEqual(self.backend.list_members(bob, group["group_id"]), [
            {"user_id": bob_id, "login_id": "bob", "role": "owner", "status": "active"}
        ])

    def test_account_deletion_is_blocked_while_user_owns_group(self) -> None:
        alice, _ = self._register("alice")
        self.backend.create_group(alice, "秘密基地")
        with self.assertRaises(ApiProblem) as caught:
            self.backend.delete_account(alice)
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "owned_groups_exist")
        self.assertIn("alice", self.cognito.users)

    def test_group_delete_requires_apps_to_be_removed_first(self) -> None:
        alice, _ = self._register("alice")
        group = self.backend.create_group(alice, "創作部屋")
        app_id = "a" * 32
        self._seed_app(group["group_id"], app_id)

        with self.assertRaises(ApiProblem) as caught:
            self.backend.delete_group(alice, group["group_id"])
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "group_has_apps")

        self._remove_seeded_app(group["group_id"], app_id)
        self.backend.delete_group(alice, group["group_id"])
        self.assertEqual(self.backend.list_groups(alice), [])

    def test_runtime_token_is_scoped_and_membership_is_rechecked_each_request(self) -> None:
        alice, _ = self._register("alice")
        bob, _ = self._register("bob")
        group = self.backend.create_group(alice, "設定資料室")
        self._join(alice, bob, group["group_id"])
        app_id = "b" * 32
        self._seed_app(group["group_id"], app_id)

        session = self.backend.create_runtime_session(bob, group["group_id"], app_id)
        saved = self.backend.set_runtime_state(
            session["token"],
            "chapter.1",
            {"title": "第一話", "draft": True},
        )
        self.assertEqual(saved["value"]["title"], "第一話")
        loaded = self.backend.get_runtime_state(session["token"], "chapter.1")
        self.assertEqual(loaded["value"], {"title": "第一話", "draft": True})

        bob_id = self.backend.me(bob)["user"]["user_id"]
        self.backend.remove_member(alice, group["group_id"], bob_id)
        with self.assertRaises(ApiProblem) as caught:
            self.backend.get_runtime_state(session["token"], "chapter.1")
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(caught.exception.error, "forbidden")

    def test_runtime_session_refuses_app_from_other_group(self) -> None:
        alice, _ = self._register("alice")
        first = self.backend.create_group(alice, "A")
        second = self.backend.create_group(alice, "B")
        app_id = "c" * 32
        self._seed_app(second["group_id"], app_id)

        with self.assertRaises(ApiProblem) as caught:
            self.backend.create_runtime_session(alice, first["group_id"], app_id)
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "app_not_found")


if __name__ == "__main__":
    unittest.main()
