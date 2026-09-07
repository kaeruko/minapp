from __future__ import annotations

import json
import pathlib
import sys
import unittest
from typing import Any
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

import abuse_entry  # noqa: E402
import hosted_authoring_delete_entry  # noqa: E402


class SentinelBackend:
    pass


def event(
    *,
    body: str | None = None,
    query: dict[str, str] | None = None,
    raw_query: str | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": "/hosted/authoring/projects/" + "3" * 32,
        "requestContext": {
            "http": {"method": "DELETE"},
            "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
        },
        "headers": {},
    }
    if body is not None:
        result["body"] = body
    if query is not None:
        result["queryStringParameters"] = query
    if raw_query is not None:
        result["rawQueryString"] = raw_query
    return result


class HostedAuthoringDeleteEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = SentinelBackend()
        hosted_authoring_delete_entry._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_authoring_delete_entry._BACKEND = None

    def test_deployed_hosted_entry_routes_delete_with_authenticated_subject(self) -> None:
        calls: list[tuple[object, str, str]] = []

        def delete(backend: object, auth_subject: str, content_id: str) -> None:
            calls.append((backend, auth_subject, content_id))

        with patch.object(hosted_authoring_delete_entry, "delete_authoring_project", delete):
            response = abuse_entry.hosted_lambda_handler(event(), None)

        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(response["body"], "")
        self.assertEqual(
            calls,
            [(self.backend, "sub-owner", "3" * 32)],
        )

    def test_delete_rejects_body_before_backend(self) -> None:
        with patch.object(hosted_authoring_delete_entry, "delete_authoring_project") as delete:
            response = abuse_entry.hosted_lambda_handler(event(body="{}"), None)

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")
        delete.assert_not_called()

    def test_delete_rejects_query_before_backend(self) -> None:
        with patch.object(hosted_authoring_delete_entry, "delete_authoring_project") as delete:
            response = abuse_entry.hosted_lambda_handler(
                event(query={"force": "true"}, raw_query="force=true"),
                None,
            )

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")
        delete.assert_not_called()


if __name__ == "__main__":
    unittest.main()
