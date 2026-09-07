from __future__ import annotations

import hashlib
import io
import sys
import unittest
import zipfile
from pathlib import Path
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
import hosted_authoring_launch  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_platform_backend import _number_attr  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


def editor_source_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", "<!doctype html><script src='editor.js'></script>")
        archive.writestr("editor.js", "window.editorLoaded = true;")
    return buffer.getvalue()


class HostedAuthoringLaunchTests(unittest.TestCase):
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
        self.group = self.backend.create_group(self.subject, "ノベル制作部")
        self.editor = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-editor",
        )
        self.project = self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            {
                "content_format": "minapp/novel@1",
                "schema_version": 1,
                "content_revision": 1,
                "title": "テスト",
                "start_scene": "start",
                "assets": {},
                "characters": {},
                "scenes": {
                    "start": {
                        "id": "start",
                        "events": [{"id": "end", "type": "end"}],
                    }
                },
            },
        )

    def test_launch_creates_authoring_content_and_ephemeral_runtime_atomically(self) -> None:
        launch = hosted_authoring_launch.create_launch(
            self.backend,
            self.subject,
            self.project["content_id"],
            self.editor["app_id"],
        )

        self.assertEqual(launch["content_id"], self.project["content_id"])
        self.assertEqual(launch["content_format"], "minapp/novel@1")
        self.assertEqual(launch["editor_app_id"], self.editor["app_id"])
        self.assertIn("publish_request", launch["allowed_operations"])
        self.assertRegex(
            launch["content_path"],
            r"^/hosted/authoring-editor/[A-Za-z0-9_-]{32,64}/index\.html$",
        )

        authoring_hash = hashlib.sha256(
            launch["authoring_token"].encode("ascii")
        ).hexdigest()
        runtime_hash = hashlib.sha256(
            launch["runtime_token"].encode("ascii")
        ).hexdigest()
        content_token = launch["content_path"].split("/")[3]
        content_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()

        authoring_item = self.metadata.items[(f"AUTHORINGSESSION#{authoring_hash}", "META")]
        content_item = self.metadata.items[(f"AUTHORINGEDITOR#{content_hash}", "META")]
        runtime_item = self.metadata.items[(f"RUNTIMESESSION#{runtime_hash}", "META")]
        self.assertEqual(authoring_item["editor_app_id"]["S"], self.editor["app_id"])
        self.assertEqual(content_item["authoring_session_hash"]["S"], authoring_hash)
        self.assertEqual(runtime_item["app_id"]["S"], self.editor["app_id"])
        self.assertIn("preview_state_id", runtime_item)

    def test_editor_file_is_read_from_immutable_builtin_source(self) -> None:
        launch = hosted_authoring_launch.create_launch(
            self.backend,
            self.subject,
            self.project["content_id"],
            self.editor["app_id"],
        )
        token = launch["content_path"].split("/")[3]

        index, index_type = hosted_authoring_launch.get_editor_file(
            self.backend,
            token,
            "index.html",
        )
        script, script_type = hosted_authoring_launch.get_editor_file(
            self.backend,
            token,
            "editor.js",
        )

        self.assertIn(b"editor.js", index)
        self.assertEqual(index_type, "text/html; charset=utf-8")
        self.assertEqual(script, b"window.editorLoaded = true;")
        self.assertEqual(script_type, "text/javascript; charset=utf-8")

    def test_expired_authoring_session_revokes_editor_content(self) -> None:
        with patch.object(hosted_authoring_launch.time, "time", return_value=100):
            launch = hosted_authoring_launch.create_launch(
                self.backend,
                self.subject,
                self.project["content_id"],
                self.editor["app_id"],
            )
        authoring_hash = hashlib.sha256(
            launch["authoring_token"].encode("ascii")
        ).hexdigest()
        self.metadata.items[(f"AUTHORINGSESSION#{authoring_hash}", "META")][
            "expires_at_epoch"
        ] = _number_attr(100)
        token = launch["content_path"].split("/")[3]

        with patch.object(hosted_authoring_launch.time, "time", return_value=100):
            with self.assertRaises(ApiProblem) as caught:
                hosted_authoring_launch.get_editor_file(
                    self.backend,
                    token,
                    "index.html",
                )
        self.assertEqual(caught.exception.status_code, 404)
        self.assertEqual(caught.exception.error, "authoring_editor_content_not_found")

    def test_non_builtin_editor_source_fails_without_partial_capabilities(self) -> None:
        editor_item = self.metadata.items[(f"APP#{self.editor['app_id']}", "META")]
        group_item = self.metadata.items[
            (f"GROUP#{self.group['group_id']}", f"APP#{self.editor['app_id']}")
        ]
        editor_item["source_kind"] = {"S": "upload"}
        group_item["source_kind"] = {"S": "upload"}
        before_keys = set(self.metadata.items)

        with self.assertRaises(ApiProblem) as caught:
            hosted_authoring_launch.create_launch(
                self.backend,
                self.subject,
                self.project["content_id"],
                self.editor["app_id"],
            )
        self.assertEqual(caught.exception.error, "editor_launch_source_unsupported")
        self.assertEqual(set(self.metadata.items), before_keys)


if __name__ == "__main__":
    unittest.main()
