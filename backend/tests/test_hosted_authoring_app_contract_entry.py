from __future__ import annotations

import json
import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

import abuse_entry  # noqa: E402
import hosted_authoring_app_contract_entry  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def _user_by_auth_subject(self, auth_subject: str) -> Any:
        self.calls.append(("user", auth_subject))
        return type("User", (), {"user_id": "user-1"})()

    def _require_active_membership(self, user_id: str, group_id: str) -> None:
        self.calls.append(("membership", user_id, group_id))

    def _group_app_items(self, group_id: str) -> list[dict[str, Any]]:
        self.calls.append(("apps", group_id))
        return [
            {
                "group_id": {"S": group_id},
                "app_id": {"S": "a" * 32},
                "title": {"S": "Quiz Editor"},
                "edits_json": {"S": '["example/quiz@1"]'},
            },
            {
                "group_id": {"S": group_id},
                "app_id": {"S": "b" * 32},
                "title": {"S": "Quiz Player"},
                "accepts_json": {"S": '["example/quiz@1"]'},
            },
        ]


def event(method: str, path: str, *, body: str | None = None, query: dict[str, str] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub-user"}}},
        },
        "headers": {},
    }
    if body is not None:
        result["body"] = body
    if query is not None:
        result["queryStringParameters"] = query
    return result


class HostedAuthoringAppContractEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        hosted_authoring_app_contract_entry._BACKEND = self.backend
        self.group_id = "2" * 32

    def tearDown(self) -> None:
        hosted_authoring_app_contract_entry._BACKEND = None

    def test_deployed_entry_lists_editor_and_player_contracts(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event("GET", f"/hosted/authoring/groups/{self.group_id}/apps"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(set(payload), {"apps"})
        self.assertEqual(payload["apps"][0]["edits"], ["example/quiz@1"])
        self.assertEqual(payload["apps"][1]["accepts"], ["example/quiz@1"])

    def test_contract_list_rejects_body_and_query_before_backend(self) -> None:
        for request in (
            event("GET", f"/hosted/authoring/groups/{self.group_id}/apps", body="{}"),
            event("GET", f"/hosted/authoring/groups/{self.group_id}/apps", query={"format": "x"}),
        ):
            with self.subTest(request=request):
                self.backend.calls.clear()
                response = abuse_entry.hosted_lambda_handler(request, None)
                self.assertEqual(response["statusCode"], 400)
                self.assertEqual(json.loads(response["body"])["error"], "invalid_request")
                self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
