from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import abuse_entry  # noqa: E402
import hosted_entry  # noqa: E402


class FakeDynamoDb:
    def __init__(self) -> None:
        self.transactions: list[list[dict[str, Any]]] = []

    def transact_write_items(self, *, TransactItems: list[dict[str, Any]]) -> None:
        self.transactions.append(TransactItems)


class FakeLaunchBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []
        self._dynamodb = FakeDynamoDb()
        self._table_name = "metadata"

    def _require_app_in_group(self, app_id: str, group_id: str) -> dict[str, Any]:
        return {
            "app_id": {"S": app_id},
            "group_id": {"S": group_id},
        }

    def _user_by_auth_subject(self, auth_subject: str) -> SimpleNamespace:
        self.last_user_subject = auth_subject
        return SimpleNamespace(user_id="1" * 32)

    def create_launch_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]:
        self.calls.append((auth_subject, group_id, app_id))
        return {
            "content_path": "/hosted/content/" + "A" * 43 + "/index.html",
            "content_expires_in": 600,
            "runtime_token": "B" * 43,
            "runtime_expires_in": 600,
            "published_version": 1,
        }


def event(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    auth: bool = False,
) -> dict[str, Any]:
    request_context: dict[str, Any] = {"http": {"method": method}}
    if auth:
        request_context["authorizer"] = {"jwt": {"claims": {"sub": "sub-member"}}}
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": request_context,
        "headers": {},
    }
    if body is not None:
        result["headers"] = {"content-type": "application/json"}
        result["body"] = json.dumps(body)
    return result


class HostedEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeLaunchBackend()
        hosted_entry._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_entry._BACKEND = None

    def test_launch_session_uses_authenticated_subject_and_empty_body(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_entry.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/launch-session",
                body={},
                auth=True,
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 201)
        payload = json.loads(response["body"])
        self.assertNotIn("access_token", payload)
        self.assertNotIn("refresh_token", payload)
        self.assertNotIn("aws_access_key_id", payload)
        self.assertEqual(
            self.backend.calls,
            [("sub-member", group_id, app_id)],
        )
        self.assertEqual(self.backend.last_user_subject, "sub-member")
        self.assertEqual(len(self.backend._dynamodb.transactions), 1)
        self.assertEqual(len(self.backend._dynamodb.transactions[0]), 3)

    def test_deployed_abuse_entry_reaches_launch_session(self) -> None:
        group_id = "4" * 32
        app_id = "5" * 32
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/launch-session",
                body={},
                auth=True,
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls,
            [("sub-member", group_id, app_id)],
        )
        self.assertEqual(len(self.backend._dynamodb.transactions), 1)

    def test_launch_session_rejects_unknown_body_fields(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_entry.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/launch-session",
                body={"runtime_token": "attacker-selected"},
                auth=True,
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.backend.calls, [])
        self.assertEqual(self.backend._dynamodb.transactions, [])

    def test_launch_session_requires_authorizer(self) -> None:
        group_id = "2" * 32
        app_id = "3" * 32
        response = hosted_entry.lambda_handler(
            event(
                "POST",
                f"/hosted/groups/{group_id}/apps/{app_id}/launch-session",
                body={},
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 401)
        self.assertEqual(self.backend.calls, [])
        self.assertEqual(self.backend._dynamodb.transactions, [])


if __name__ == "__main__":
    unittest.main()
