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
import hosted_authoring_entry  # noqa: E402


class FakeListBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []

    def list_authoring_projects(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        self.calls.append(("list", auth_subject, group_id))
        return [
            {
                "content_id": "3" * 32,
                "group_id": group_id,
                "content_format": "minapp/novel@1",
                "status": "draft",
                "draft_revision": 4,
                "assets": [],
                "created_at": "2026-09-06T09:00:00Z",
                "updated_at": "2026-09-06T10:00:00Z",
            }
        ]


def event(method: str, path: str, *, body: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
        },
        "headers": {},
    }
    if body is not None:
        result["body"] = body
    return result


class HostedAuthoringListEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeListBackend()
        hosted_authoring_entry._BACKEND = self.backend
        self.group_id = "2" * 32

    def tearDown(self) -> None:
        hosted_authoring_entry._BACKEND = None

    def test_deployed_hosted_entry_lists_group_projects(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event("GET", f"/hosted/authoring/groups/{self.group_id}/projects"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.calls, [("list", "sub-owner", self.group_id)])
        payload = json.loads(response["body"])
        self.assertEqual(set(payload), {"projects"})
        self.assertEqual(payload["projects"][0]["content_format"], "minapp/novel@1")

    def test_list_rejects_body_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "GET",
                f"/hosted/authoring/groups/{self.group_id}/projects",
                body="{}",
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")
        self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
