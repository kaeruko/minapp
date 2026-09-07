from __future__ import annotations

import hashlib
import io
import json
import os
import sys
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
import hosted_authoring_capability_entry  # noqa: E402
import hosted_authoring_launch  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_authoring_web_bridge import (  # noqa: E402
    HOST_ADAPTER_WEB,
    inject_web_bridge,
)
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


def editor_source_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><script>window.beforeBridge = true;</script>",
        )
        archive.writestr("editor.js", "window.editorLoaded = true;")
    return buffer.getvalue()


class HostedAuthoringWebBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = AuthoringFakeDynamoDb()
        self.runtime = AuthoringFakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-editor/v1/source.zip")
        ] = editor_source_zip()
        self.backend = HostedAuthoringPublishBackend(
            cognito=self.cognito,
            dynamodb=self.metadata,
            runtime_dynamodb=self.runtime,
            s3=self.s3,
            user_pool_id="pool",
            app_client_id="client",
            table_name="metadata",
            runtime_table_name="runtime",
            upload_bucket="uploads",
            published_bucket="published",
        )
        self.backend.register("alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)
        self.subject = self.cognito.users["alice"]["sub"]
        self.group = self.backend.create_group(self.subject, "Web制作部")
        self.editor = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-editor",
        )
        self.project = self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {},
        )

    def test_web_launch_injects_postmessage_bridge_without_capability_tokens(self) -> None:
        with patch.dict(os.environ, {"PORTAL_ORIGIN": "https://portal.example.test"}):
            launch = hosted_authoring_launch.create_launch(
                self.backend,
                self.subject,
                self.project["content_id"],
                self.editor["app_id"],
                host_adapter=HOST_ADAPTER_WEB,
            )

        self.assertRegex(launch["web_bridge_nonce"], r"^[A-Za-z0-9_-]{32,64}$")
        token = launch["content_path"].split("/")[3]
        content_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        content_item = self.metadata.items[(f"AUTHORINGEDITOR#{content_hash}", "META")]
        self.assertEqual(content_item["host_adapter"]["S"], "web")
        self.assertEqual(content_item["web_parent_origin"]["S"], "https://portal.example.test")
        self.assertEqual(content_item["web_bridge_nonce"]["S"], launch["web_bridge_nonce"])

        index, content_type = hosted_authoring_launch.get_editor_file(
            self.backend,
            token,
            "index.html",
        )
        source = index.decode("utf-8")
        self.assertEqual(content_type, "text/html; charset=utf-8")
        self.assertIn("window.beforeBridge = true", source)
        self.assertIn("minapp.web", source)
        self.assertIn("authoring.preview", source)
        self.assertIn("userState.set", source)
        self.assertIn("https://portal.example.test", source)
        self.assertIn(launch["web_bridge_nonce"], source)
        self.assertNotIn(launch["authoring_token"], source)
        self.assertNotIn(launch["runtime_token"], source)

        script, script_type = hosted_authoring_launch.get_editor_file(
            self.backend,
            token,
            "editor.js",
        )
        self.assertEqual(script, b"window.editorLoaded = true;")
        self.assertEqual(script_type, "text/javascript; charset=utf-8")

    def test_native_launch_remains_unmodified(self) -> None:
        launch = hosted_authoring_launch.create_launch(
            self.backend,
            self.subject,
            self.project["content_id"],
            self.editor["app_id"],
        )
        self.assertNotIn("web_bridge_nonce", launch)
        token = launch["content_path"].split("/")[3]
        index, _ = hosted_authoring_launch.get_editor_file(
            self.backend,
            token,
            "index.html",
        )
        self.assertEqual(
            index,
            b"<!doctype html><script>window.beforeBridge = true;</script>",
        )

    def test_missing_web_parent_configuration_fails_before_session_creation(self) -> None:
        before_keys = set(self.metadata.items)
        with patch.dict(os.environ, {"PORTAL_ORIGIN": ""}):
            with self.assertRaises(ApiProblem) as caught:
                hosted_authoring_launch.create_launch(
                    self.backend,
                    self.subject,
                    self.project["content_id"],
                    self.editor["app_id"],
                    host_adapter=HOST_ADAPTER_WEB,
                )
        self.assertEqual(caught.exception.status_code, 503)
        self.assertEqual(caught.exception.error, "web_authoring_host_unavailable")
        self.assertEqual(set(self.metadata.items), before_keys)

    def test_invalid_utf8_editor_is_rejected_instead_of_reencoded(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            inject_web_bridge(
                b"\xff\xfe",
                parent_origin="https://portal.example.test",
                bridge_nonce="a" * 43,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "authoring_editor_web_incompatible")


class HostedAuthoringWebEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = object()
        hosted_authoring_capability_entry._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_authoring_capability_entry._BACKEND = None

    def event(self, payload: dict[str, object]) -> dict[str, object]:
        return {
            "rawPath": "/hosted/authoring/projects/" + "3" * 32 + "/launch",
            "requestContext": {
                "http": {"method": "POST"},
                "authorizer": {"jwt": {"claims": {"sub": "sub-owner"}}},
            },
            "headers": {"content-type": "application/json"},
            "body": json.dumps(payload),
        }

    def test_launch_entry_passes_explicit_web_adapter(self) -> None:
        response_payload = {
            "content_path": "/hosted/authoring-editor/" + "x" * 43 + "/index.html",
            "content_expires_in": 600,
            "runtime_token": "r" * 43,
            "runtime_expires_in": 900,
            "authoring_token": "a" * 43,
            "authoring_expires_in": 600,
            "content_id": "3" * 32,
            "content_format": "example/quiz@1",
            "editor_app_id": "4" * 32,
            "allowed_operations": ["load", "save_document", "preview_request", "publish_request"],
            "web_bridge_nonce": "n" * 43,
        }
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_launch,
            "create_launch",
            return_value=response_payload,
        ) as create_launch:
            response = hosted_authoring_capability_entry.handle_request(
                self.event({"editor_app_id": "4" * 32, "host_adapter": "web"})
            )
        self.assertIsNotNone(response)
        assert response is not None
        self.assertEqual(response["statusCode"], 201)
        create_launch.assert_called_once_with(
            self.backend,
            "sub-owner",
            "3" * 32,
            "4" * 32,
            host_adapter="web",
        )

    def test_launch_entry_rejects_unknown_adapter_before_backend_call(self) -> None:
        with patch.object(
            hosted_authoring_capability_entry.hosted_authoring_launch,
            "create_launch",
        ) as create_launch:
            with self.assertRaises(ApiProblem) as caught:
                hosted_authoring_capability_entry.handle_request(
                    self.event({"editor_app_id": "4" * 32, "host_adapter": "mystery"})
                )
        self.assertEqual(caught.exception.status_code, 400)
        self.assertEqual(caught.exception.error, "invalid_request")
        create_launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
