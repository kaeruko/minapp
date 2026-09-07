from __future__ import annotations

import base64
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


class FakeAuthoringBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def create_authoring_project(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        self.calls.append(("create", auth_subject, group_id, content_format, document))
        return {
            "content_id": "3" * 32,
            "group_id": group_id,
            "content_format": content_format,
            "status": "draft",
            "draft_revision": 1,
            "assets": [],
            "created_at": "2026-09-06T09:00:00Z",
            "updated_at": "2026-09-06T09:00:00Z",
        }

    def list_authoring_apps(
        self,
        auth_subject: str,
        group_id: str,
    ) -> list[dict[str, Any]]:
        self.calls.append(("apps", auth_subject, group_id))
        return [
            {
                "app_id": "4" * 32,
                "group_id": group_id,
                "title": "Quiz Editor",
                "edits": ["example/quiz@1"],
                "accepts": [],
            },
            {
                "app_id": "5" * 32,
                "group_id": group_id,
                "title": "Quiz Player",
                "edits": [],
                "accepts": ["example/quiz@1"],
            },
        ]

    def list_authoring_projects(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str | None = None,
    ) -> list[dict[str, Any]]:
        self.calls.append(("projects", auth_subject, group_id, content_format))
        return []

    def load_authoring_project(self, auth_subject: str, content_id: str) -> dict[str, Any]:
        self.calls.append(("load", auth_subject, content_id))
        return {
            "content_id": content_id,
            "group_id": "2" * 32,
            "content_format": "minapp/novel@1",
            "status": "draft",
            "draft_revision": 2,
            "assets": [],
            "created_at": "2026-09-06T09:00:00Z",
            "updated_at": "2026-09-06T09:10:00Z",
            "document": {"version": 1},
        }

    def save_authoring_document(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        self.calls.append(("document", auth_subject, content_id, expected_revision, document))
        return {
            "content_id": content_id,
            "group_id": "2" * 32,
            "content_format": "minapp/novel@1",
            "status": "draft",
            "draft_revision": expected_revision + 1,
            "assets": [],
            "created_at": "2026-09-06T09:00:00Z",
            "updated_at": "2026-09-06T09:10:00Z",
        }

    def get_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        path: str,
    ) -> tuple[bytes, str]:
        self.calls.append(("asset-get", auth_subject, content_id, path))
        return b"OggS", "audio/ogg"

    def save_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
        data: bytes,
    ) -> dict[str, Any]:
        self.calls.append(("asset-save", auth_subject, content_id, expected_revision, path, data))
        return {
            "content_id": content_id,
            "group_id": "2" * 32,
            "content_format": "minapp/novel@1",
            "status": "draft",
            "draft_revision": expected_revision + 1,
            "assets": [{"path": path, "bytes": len(data), "content_type": "audio/ogg", "sha256": "a" * 64, "revision": expected_revision + 1}],
            "created_at": "2026-09-06T09:00:00Z",
            "updated_at": "2026-09-06T09:10:00Z",
        }

    def delete_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
    ) -> dict[str, Any]:
        self.calls.append(("asset-delete", auth_subject, content_id, expected_revision, path))
        return {
            "content_id": content_id,
            "group_id": "2" * 32,
            "content_format": "minapp/novel@1",
            "status": "draft",
            "draft_revision": expected_revision + 1,
            "assets": [],
            "created_at": "2026-09-06T09:00:00Z",
            "updated_at": "2026-09-06T09:10:00Z",
        }


def event(
    method: str,
    path: str,
    *,
    body: str | None = None,
    content_type: str | None = None,
    base64_encoded: bool = False,
    extra_headers: dict[str, str] | None = None,
    query: dict[str, str] | None = None,
) -> dict[str, Any]:
    headers: dict[str, str] = {}
    if content_type is not None:
        headers["content-type"] = content_type
    if extra_headers:
        headers.update(extra_headers)
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
        },
        "headers": headers,
    }
    if body is not None:
        result["body"] = body
    if base64_encoded:
        result["isBase64Encoded"] = True
    if query is not None:
        result["queryStringParameters"] = query
    return result


class HostedAuthoringEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeAuthoringBackend()
        hosted_authoring_entry._BACKEND = self.backend
        self.group_id = "2" * 32
        self.content_id = "3" * 32

    def tearDown(self) -> None:
        hosted_authoring_entry._BACKEND = None

    def test_deployed_hosted_entry_creates_and_loads_project(self) -> None:
        create_response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                "/hosted/authoring/projects",
                content_type="application/json",
                body=json.dumps(
                    {
                        "group_id": self.group_id,
                        "content_format": "minapp/novel@1",
                        "document": {"version": 1},
                    }
                ),
            ),
            None,
        )
        self.assertEqual(create_response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls[0],
            ("create", "sub-owner", self.group_id, "minapp/novel@1", {"version": 1}),
        )

        load_response = abuse_entry.hosted_lambda_handler(
            event("GET", f"/hosted/authoring/projects/{self.content_id}"),
            None,
        )
        self.assertEqual(load_response["statusCode"], 200)
        self.assertEqual(json.loads(load_response["body"])["document"], {"version": 1})
        self.assertEqual(self.backend.calls[1], ("load", "sub-owner", self.content_id))

    def test_group_authoring_apps_route_uses_authenticated_subject(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event("GET", f"/hosted/authoring/groups/{self.group_id}/apps"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(
            payload,
            {
                "apps": [
                    {
                        "app_id": "4" * 32,
                        "group_id": self.group_id,
                        "title": "Quiz Editor",
                        "edits": ["example/quiz@1"],
                        "accepts": [],
                    },
                    {
                        "app_id": "5" * 32,
                        "group_id": self.group_id,
                        "title": "Quiz Player",
                        "edits": [],
                        "accepts": ["example/quiz@1"],
                    },
                ]
            },
        )
        self.assertEqual(self.backend.calls, [("apps", "sub-owner", self.group_id)])

    def test_group_authoring_apps_rejects_query_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "GET",
                f"/hosted/authoring/groups/{self.group_id}/apps",
                query={"content_format": "example/quiz@1"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")
        self.assertEqual(self.backend.calls, [])

    def test_document_save_passes_explicit_expected_revision(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                f"/hosted/authoring/projects/{self.content_id}/document",
                content_type="application/json",
                body=json.dumps(
                    {"expected_revision": 7, "document": {"version": 1, "start": "end"}}
                ),
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("document", "sub-owner", self.content_id, 7, {"version": 1, "start": "end"})],
        )

    def test_asset_save_requires_matching_type_and_revision_header(self) -> None:
        raw = b"OggS-audio"
        path = f"/hosted/authoring/projects/{self.content_id}/assets/audio/bgm.ogg"
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                path,
                content_type="audio/ogg",
                body=base64.b64encode(raw).decode("ascii"),
                base64_encoded=True,
                extra_headers={"x-minapp-expected-revision": "3"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.backend.calls,
            [("asset-save", "sub-owner", self.content_id, 3, "audio/bgm.ogg", raw)],
        )

    def test_asset_content_type_mismatch_stops_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                f"/hosted/authoring/projects/{self.content_id}/assets/audio/bgm.ogg",
                content_type="audio/mpeg",
                body=base64.b64encode(b"OggS").decode("ascii"),
                base64_encoded=True,
                extra_headers={"x-minapp-expected-revision": "1"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 415)
        self.assertEqual(json.loads(response["body"])["error"], "authoring_asset_content_type_mismatch")
        self.assertEqual(self.backend.calls, [])

    def test_unknown_create_field_is_rejected_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                "/hosted/authoring/projects",
                content_type="application/json",
                body=json.dumps(
                    {
                        "group_id": self.group_id,
                        "content_format": "minapp/novel@1",
                        "document": {"version": 1},
                        "content_id": "4" * 32,
                    }
                ),
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
