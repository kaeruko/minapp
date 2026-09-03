from __future__ import annotations

import base64
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_entry  # noqa: E402


class HostedUploadEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = object()
        hosted_entry._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        hosted_entry._BACKEND = None

    def _event(self, *, title: str = "放課後アプリ") -> dict[str, object]:
        return {
            "rawPath": "/hosted/groups/" + "2" * 32 + "/apps/upload",
            "requestContext": {
                "http": {"method": "POST"},
                "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
            },
            "headers": {"content-type": "application/zip"},
            "queryStringParameters": {"title": title},
            "isBase64Encoded": True,
            "body": base64.b64encode(b"PK-test-zip").decode("ascii"),
        }

    def test_upload_route_passes_exact_zip_and_title(self) -> None:
        expected = {
            "app_id": "3" * 32,
            "group_id": "2" * 32,
            "title": "放課後アプリ",
            "source_kind": "upload",
            "created_at": "2026-09-03T00:00:00Z",
            "source_revision": 1,
            "editable": True,
        }
        with patch.object(hosted_entry, "create_uploaded_app", return_value=expected) as create:
            response = hosted_entry.lambda_handler(self._event(), None)

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"]), expected)
        create.assert_called_once_with(
            self.backend,
            "sub-owner",
            "2" * 32,
            "放課後アプリ",
            b"PK-test-zip",
        )

    def test_upload_route_requires_exact_title_query(self) -> None:
        event = self._event()
        event["queryStringParameters"] = {"title": "x", "extra": "no"}
        with patch.object(hosted_entry, "create_uploaded_app") as create:
            response = hosted_entry.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 400)
        create.assert_not_called()

    def test_upload_route_requires_zip_content_type(self) -> None:
        event = self._event()
        event["headers"] = {"content-type": "application/json"}
        with patch.object(hosted_entry, "create_uploaded_app") as create:
            response = hosted_entry.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 415)
        create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
