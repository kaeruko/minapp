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
import hosted_authoring_publish_entry  # noqa: E402


class FakePublishBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def publish_authoring_project(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
    ) -> dict[str, Any]:
        self.calls.append((auth_subject, content_id, expected_revision))
        return {
            "content_id": content_id,
            "group_id": "2" * 32,
            "content_format": "minapp/novel@1",
            "published_version": 3,
            "source_revision": expected_revision,
            "assets": [],
            "published_at": "2026-09-06T10:00:00Z",
        }


def event(method: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
        },
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


class HostedAuthoringPublishEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakePublishBackend()
        hosted_authoring_publish_entry._BACKEND = self.backend
        self.content_id = "3" * 32

    def tearDown(self) -> None:
        hosted_authoring_publish_entry._BACKEND = None

    def test_deployed_entry_publishes_explicit_revision(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                f"/hosted/authoring/projects/{self.content_id}/publish",
                {"expected_revision": 7},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"])["source_revision"], 7)
        self.assertEqual(self.backend.calls, [("sub-owner", self.content_id, 7)])

    def test_publish_rejects_unknown_fields_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                f"/hosted/authoring/projects/{self.content_id}/publish",
                {"expected_revision": 7, "force": True},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
