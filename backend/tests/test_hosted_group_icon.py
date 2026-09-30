from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_backend import HostedAwsBackend  # noqa: E402
from hosted_group_icon import delete_group_icon, get_group_icon, set_group_icon  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402


class HostedGroupIconTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.backend = HostedAwsBackend(
            cognito=self.cognito,
            dynamodb=self.dynamo,
            user_pool_id="pool",
            app_client_id="client",
            table_name="table",
        )
        self.alice = self._register("alice")
        self.bob = self._register("bob")
        self.charlie = self._register("charlie")
        self.group = self.backend.create_group(self.alice, "アイコン部")
        invite = self.backend.create_invite(self.alice, self.group["group_id"])
        self.backend.join_group(self.bob, invite["code"])

    def _register(self, login_id: str) -> str:
        self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"]

    def test_owner_sets_icon_and_member_reads_same_bytes(self) -> None:
        data = b"\x89PNG\r\n\x1a\ngroup-icon"
        saved = set_group_icon(
            self.backend,
            self.alice,
            self.group["group_id"],
            data=data,
            content_type="image/png",
        )
        self.assertEqual(saved["group_id"], self.group["group_id"])
        self.assertEqual(saved["content_type"], "image/png")
        self.assertEqual(saved["bytes"], len(data))

        stored, content_type = get_group_icon(
            self.backend,
            self.bob,
            self.group["group_id"],
        )
        self.assertEqual(stored, data)
        self.assertEqual(content_type, "image/png")

    def test_non_owner_cannot_change_or_delete_icon(self) -> None:
        data = b"RIFF\x00\x00\x00\x00WEBPgroup-icon"
        for operation in (
            lambda: set_group_icon(
                self.backend,
                self.bob,
                self.group["group_id"],
                data=data,
                content_type="image/webp",
            ),
            lambda: delete_group_icon(
                self.backend,
                self.bob,
                self.group["group_id"],
            ),
        ):
            with self.assertRaises(ApiProblem) as denied:
                operation()
            self.assertEqual(denied.exception.status_code, 403)

    def test_outsider_cannot_read_group_icon(self) -> None:
        data = b"\xff\xd8\xffgroup-icon"
        set_group_icon(
            self.backend,
            self.alice,
            self.group["group_id"],
            data=data,
            content_type="image/jpeg",
        )

        with self.assertRaises(ApiProblem) as denied:
            get_group_icon(
                self.backend,
                self.charlie,
                self.group["group_id"],
            )
        self.assertEqual(denied.exception.status_code, 403)

    def test_delete_restores_missing_icon_state(self) -> None:
        data = b"\x89PNG\r\n\x1a\ngroup-icon"
        set_group_icon(
            self.backend,
            self.alice,
            self.group["group_id"],
            data=data,
            content_type="image/png",
        )

        delete_group_icon(
            self.backend,
            self.alice,
            self.group["group_id"],
        )

        with self.assertRaises(ApiProblem) as missing:
            get_group_icon(
                self.backend,
                self.alice,
                self.group["group_id"],
            )
        self.assertEqual(missing.exception.status_code, 404)
        self.assertEqual(missing.exception.error, "group_icon_not_found")


if __name__ == "__main__":
    unittest.main()
