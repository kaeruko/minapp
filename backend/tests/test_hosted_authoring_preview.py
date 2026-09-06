from __future__ import annotations

import hashlib
import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
import hosted_authoring_preview  # noqa: E402
from hosted_authoring_publish_backend import HostedAuthoringPublishBackend  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from test_hosted_authoring_backend import AuthoringFakeDynamoDb  # noqa: E402
from test_hosted_backend import FakeCognito  # noqa: E402
from test_hosted_catalog_backend import FakeS3  # noqa: E402


def player_source_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            "<!doctype html><title>template</title>"
            "<script id='minapp-novel-story' type='application/json'>"
            '{"title":"template"}'
            "</script><script src='player.js'></script>",
        )
        archive.writestr("player.js", "window.playerLoaded = true;")
    return buffer.getvalue()


def editor_source_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", "<!doctype html><script src='editor.js'></script>")
        archive.writestr("editor.js", "window.editorLoaded = true;")
    return buffer.getvalue()


def document(title: str, revision: int = 1) -> dict[str, object]:
    return {
        "content_format": "minapp/novel@1",
        "schema_version": 1,
        "content_revision": revision,
        "title": title,
        "start_scene": "start",
        "assets": {},
        "characters": {},
        "scenes": {
            "start": {
                "id": "start",
                "events": [{"id": "end", "type": "end"}],
            }
        },
    }


class HostedAuthoringPreviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = AuthoringFakeDynamoDb()
        self.runtime = AuthoringFakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-starter/v4/source.zip")
        ] = player_source_zip()
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
        self.player = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-starter",
        )
        self.editor = self.backend.install_builtin(
            self.subject,
            self.group["group_id"],
            "novel-editor",
        )
        self.project = self.backend.create_authoring_project(
            self.subject,
            self.group["group_id"],
            "minapp/novel@1",
            document("Draft One"),
        )

    def _preview(self, revision: int = 1) -> dict[str, object]:
        return hosted_authoring_preview.create_preview(
            self.backend,
            self.subject,
            self.project["content_id"],
            self.player["app_id"],
            expected_revision=revision,
        )

    def test_preview_atomically_binds_draft_player_and_ephemeral_runtime(self) -> None:
        preview = self._preview()

        self.assertEqual(preview["content_id"], self.project["content_id"])
        self.assertEqual(preview["content_format"], "minapp/novel@1")
        self.assertEqual(preview["draft_revision"], 1)
        self.assertEqual(preview["player_app_id"], self.player["app_id"])
        self.assertRegex(
            str(preview["content_path"]),
            r"^/hosted/authoring-preview/[A-Za-z0-9_-]{32,64}/index\.html$",
        )

        content_token = str(preview["content_path"]).split("/")[3]
        content_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
        runtime_hash = hashlib.sha256(str(preview["runtime_token"]).encode("ascii")).hexdigest()
        content_item = self.metadata.items[(f"AUTHORINGPREVIEW#{content_hash}", "META")]
        runtime_item = self.metadata.items[(f"RUNTIMESESSION#{runtime_hash}", "META")]
        self.assertEqual(content_item["draft_revision"]["N"], "1")
        self.assertEqual(content_item["player_app_id"]["S"], self.player["app_id"])
        self.assertEqual(runtime_item["app_id"]["S"], self.player["app_id"])
        self.assertIn("preview_state_id", runtime_item)

    def test_index_embeds_pinned_master_data_and_escapes_script_termination(self) -> None:
        updated = self.backend.save_authoring_document(
            self.subject,
            self.project["content_id"],
            expected_revision=1,
            document=document("</script><script>alert(1)</script>", revision=2),
        )
        preview = self._preview(revision=updated["draft_revision"])
        token = str(preview["content_path"]).split("/")[3]

        index, content_type = hosted_authoring_preview.get_preview_file(
            self.backend,
            token,
            "index.html",
        )
        text = index.decode("utf-8")
        self.assertEqual(content_type, "text/html; charset=utf-8")
        self.assertNotIn("</script><script>alert(1)</script>", text)
        self.assertIn(r"\u003c/script\u003e\u003cscript\u003ealert(1)", text)
        self.assertIn('"content_revision":2', text)

    def test_preview_stays_pinned_when_current_draft_advances(self) -> None:
        preview = self._preview(revision=1)
        token = str(preview["content_path"]).split("/")[3]
        self.backend.save_authoring_document(
            self.subject,
            self.project["content_id"],
            expected_revision=1,
            document=document("Draft Two", revision=2),
        )

        index, _ = hosted_authoring_preview.get_preview_file(
            self.backend,
            token,
            "index.html",
        )
        text = index.decode("utf-8")
        self.assertIn('"title":"Draft One"', text)
        self.assertNotIn('"title":"Draft Two"', text)

    def test_project_assets_are_served_from_the_pinned_revision(self) -> None:
        saved = self.backend.save_authoring_asset(
            self.subject,
            self.project["content_id"],
            expected_revision=1,
            path="images/face.png",
            data=b"PNG-DRAFT-ONE",
        )
        preview = self._preview(revision=saved["draft_revision"])
        token = str(preview["content_path"]).split("/")[3]

        data, content_type = hosted_authoring_preview.get_preview_file(
            self.backend,
            token,
            "images/face.png",
        )
        self.assertEqual(data, b"PNG-DRAFT-ONE")
        self.assertEqual(content_type, "image/png")

    def test_source_asset_collision_fails_before_any_capability_is_created(self) -> None:
        saved = self.backend.save_authoring_asset(
            self.subject,
            self.project["content_id"],
            expected_revision=1,
            path="player.js",
            data=b"not actually javascript",
        )
        before_keys = set(self.metadata.items)

        with self.assertRaises(ApiProblem) as caught:
            self._preview(revision=saved["draft_revision"])
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "authoring_preview_asset_collision")
        self.assertEqual(set(self.metadata.items), before_keys)

    def test_editor_cannot_be_used_as_player(self) -> None:
        before_keys = set(self.metadata.items)
        with self.assertRaises(ApiProblem) as caught:
            hosted_authoring_preview.create_preview(
                self.backend,
                self.subject,
                self.project["content_id"],
                self.editor["app_id"],
                expected_revision=1,
            )
        self.assertEqual(caught.exception.error, "player_not_authoring_capable")
        self.assertEqual(set(self.metadata.items), before_keys)


if __name__ == "__main__":
    unittest.main()
