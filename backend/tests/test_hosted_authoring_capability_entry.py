from __future__ import annotations

import base64
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
import hosted_authoring_capability_entry  # noqa: E402


class SentinelBackend:
    pass


def event(
    method: str,
    path: str,
    *,
    body: str | None = None,
    content_type: str | None = None,
    base64_encoded: bool = False,
    auth: bool = False,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    headers: dict[str, str] = {}
    if content_type is not None:
        headers["content-type"] = content_type
    if extra_headers:
        headers.update(extra_headers)
    request_context: dict[str, Any] = {"http": {"method": method}}
    if auth:
        request_context["authorizer"] = {"jwt": {"claims": {"sub": "sub-owner"}}}
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": request_context,
        "headers": headers,
    }
    if body is not None:
        result["body"] = body
    if base64_encoded:
        result["isBase64Encoded"] = True
    return result


class HostedAuthoringCapabilityEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = SentinelBackend()
        hosted_authoring_capability_entry._BACKEND = self.backend
        self.content_id = "3" * 32
        self.editor_app_id = "4" * 32
        self.player_app_id = "5" * 32
        self.token = "A" * 43

    def tearDown(self) -> None:
        hosted_authoring_capability_entry._BACKEND = None

    def test_session_mint_requires_authenticated_subject_and_exact_editor_id(self) -> None:
        expected = {
            "token": self.token,
            "expires_in": 600,
            "content_id": self.content_id,
            "content_format": "minapp/novel@1",
            "editor_app_id": self.editor_app_id,
            "allowed_operations": ["load"],
        }
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_session,
            "create_session",
            return_value=expected,
        ) as create:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/projects/{self.content_id}/session",
                    content_type="application/json",
                    body=json.dumps({"editor_app_id": self.editor_app_id}),
                    auth=True,
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"]), expected)
        create.assert_called_once_with(
            self.backend,
            "sub-owner",
            self.content_id,
            self.editor_app_id,
        )

    def test_structured_preview_requires_jwt_and_explicit_player_revision(self) -> None:
        expected = {
            "content_id": self.content_id,
            "content_format": "minapp/novel@1",
            "draft_revision": 7,
            "player_app_id": self.player_app_id,
            "content_path": f"/hosted/authoring-preview/{self.token}/index.html",
            "expires_in": 600,
            "runtime_token": "R" * 43,
            "runtime_expires_in": 600,
        }
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_preview,
            "create_preview",
            return_value=expected,
        ) as create:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/projects/{self.content_id}/preview",
                    content_type="application/json",
                    body=json.dumps(
                        {"player_app_id": self.player_app_id, "expected_revision": 7}
                    ),
                    auth=True,
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(json.loads(response["body"]), expected)
        create.assert_called_once_with(
            self.backend,
            "sub-owner",
            self.content_id,
            self.player_app_id,
            expected_revision=7,
        )

    def test_structured_preview_content_is_capability_only(self) -> None:
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_preview,
            "get_preview_file",
            return_value=(b"<!doctype html>", "text/html; charset=utf-8"),
        ) as get_file:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "GET",
                    f"/hosted/authoring-preview/{self.token}/index.html",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        get_file.assert_called_once_with(self.backend, self.token, "index.html")

    def test_capability_load_does_not_require_cognito_or_accept_content_id(self) -> None:
        expected = {"content_id": self.content_id, "draft_revision": 7, "document": {"version": 1}}
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_session,
            "load_project",
            return_value=expected,
        ) as load:
            response = abuse_entry.hosted_lambda_handler(
                event("GET", f"/hosted/authoring/session/{self.token}"),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), expected)
        load.assert_called_once_with(self.backend, self.token)

    def test_capability_document_save_passes_revision_but_not_identity_scope(self) -> None:
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_session,
            "save_document",
            return_value={"content_id": self.content_id, "draft_revision": 8},
        ) as save:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/session/{self.token}/document",
                    content_type="application/json",
                    body=json.dumps(
                        {"expected_revision": 7, "document": {"version": 1, "start": "end"}}
                    ),
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        save.assert_called_once_with(
            self.backend,
            self.token,
            expected_revision=7,
            document={"version": 1, "start": "end"},
        )

    def test_capability_asset_save_keeps_binary_type_and_explicit_revision(self) -> None:
        raw = b"OggS-editor"
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_session,
            "save_asset",
            return_value={"content_id": self.content_id, "draft_revision": 9},
        ) as save:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/session/{self.token}/assets/audio/bgm.ogg",
                    content_type="audio/ogg",
                    body=base64.b64encode(raw).decode("ascii"),
                    base64_encoded=True,
                    extra_headers={"x-minapp-expected-revision": "8"},
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        save.assert_called_once_with(
            self.backend,
            self.token,
            expected_revision=8,
            path="audio/bgm.ogg",
            data=raw,
        )

    def test_session_mint_rejects_unknown_fields_before_backend(self) -> None:
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_session,
            "create_session",
        ) as create:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/projects/{self.content_id}/session",
                    content_type="application/json",
                    body=json.dumps(
                        {"editor_app_id": self.editor_app_id, "content_format": "minapp/novel@1"}
                    ),
                    auth=True,
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 400)
        create.assert_not_called()

    def test_preview_rejects_unknown_scope_fields_before_backend(self) -> None:
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_preview,
            "create_preview",
        ) as create:
            response = abuse_entry.hosted_lambda_handler(
                event(
                    "POST",
                    f"/hosted/authoring/projects/{self.content_id}/preview",
                    content_type="application/json",
                    body=json.dumps(
                        {
                            "player_app_id": self.player_app_id,
                            "expected_revision": 7,
                            "group_id": "6" * 32,
                        }
                    ),
                    auth=True,
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 400)
        create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
