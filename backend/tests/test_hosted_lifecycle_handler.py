from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_handler  # noqa: E402
from test_hosted_handler import event  # noqa: E402


class FakeLifecycleBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def recover_account(self, login_id: str, recovery_code: str, new_password: str) -> dict[str, Any]:
        self.calls.append(("recover_account", login_id, recovery_code, new_password))
        return {"login_id": login_id, "recovery_code": "2345-6789-ABCD-EFGH-JKLM"}

    def rotate_recovery_code(self, auth_subject: str) -> dict[str, str]:
        self.calls.append(("rotate_recovery_code", auth_subject))
        return {"recovery_code": "2345-6789-ABCD-EFGH-JKLM"}

    def delete_account(self, auth_subject: str) -> None:
        self.calls.append(("delete_account", auth_subject))

    def transfer_group_ownership(
        self, auth_subject: str, group_id: str, new_owner_user_id: str
    ) -> dict[str, str]:
        self.calls.append(("transfer_group_ownership", auth_subject, group_id, new_owner_user_id))
        return {"group_id": group_id, "owner_user_id": new_owner_user_id}

    def delete_group(self, auth_subject: str, group_id: str) -> None:
        self.calls.append(("delete_group", auth_subject, group_id))

    def create_runtime_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]:
        self.calls.append(("create_runtime_session", auth_subject, group_id, app_id))
        return {"token": "a" * 43, "expires_in": 600}

    def get_runtime_state(self, token: str, key: str) -> dict[str, Any]:
        self.calls.append(("get_runtime_state", token, key))
        return {"key": key, "value": {"x": 1}, "updated_at": "2026-08-27T00:00:00Z"}

    def set_runtime_state(self, token: str, key: str, value: Any) -> dict[str, Any]:
        self.calls.append(("set_runtime_state", token, key, value))
        return {"key": key, "value": value, "updated_at": "2026-08-27T00:00:00Z"}

    def delete_runtime_state(self, token: str, key: str) -> None:
        self.calls.append(("delete_runtime_state", token, key))


class HostedLifecycleHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeLifecycleBackend()
        hosted_handler._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_handler._BACKEND = None

    def test_recovery_is_public_and_requires_exact_fields(self) -> None:
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                "/hosted/recover",
                body={
                    "login_id": "alice",
                    "recovery_code": "2345-6789-ABCD-EFGH-JKLM",
                    "new_password": "newsecret12",
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("recover_account", "alice", "2345-6789-ABCD-EFGH-JKLM", "newsecret12")],
        )

    def test_account_delete_uses_authenticated_subject(self) -> None:
        response = hosted_handler.lambda_handler(event("DELETE", "/hosted/account", auth=True), None)
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(self.backend.calls, [("delete_account", "sub-alice")])

    def test_owner_transfer_validates_user_id(self) -> None:
        group_id = "2" * 32
        user_id = "3" * 32
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/owner",
                body={"user_id": user_id},
                auth=True,
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("transfer_group_ownership", "sub-alice", group_id, user_id)],
        )

    def test_runtime_session_requires_authenticated_subject(self) -> None:
        group_id = "2" * 32
        app_id = "4" * 32
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/runtime-session",
                body={},
                auth=True,
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls,
            [("create_runtime_session", "sub-alice", group_id, app_id)],
        )

    def test_runtime_state_uses_scoped_token_without_cognito_authorizer(self) -> None:
        token = "a" * 43
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                f"/hosted/runtime/{token}/state/chapter.1",
                body={"value": {"title": "第一話"}},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("set_runtime_state", token, "chapter.1", {"title": "第一話"})],
        )
        body = json.loads(response["body"])
        self.assertEqual(body["value"]["title"], "第一話")


if __name__ == "__main__":
    unittest.main()
