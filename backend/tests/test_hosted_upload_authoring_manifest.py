from __future__ import annotations

import io
import json
import sys
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_upload import create_uploaded_app  # noqa: E402


def make_zip(manifest: object | None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", "<!doctype html><title>test</title>")
        if manifest is not None:
            archive.writestr(
                "minapp.json",
                json.dumps(manifest, separators=(",", ":")),
            )
    return buffer.getvalue()


class FakeUploadBackend:
    def __init__(self) -> None:
        self._upload_bucket = "uploads"
        self.items: list[dict[str, object]] | None = None
        self.put_count = 0

    def _user_by_auth_subject(self, auth_subject: str) -> SimpleNamespace:
        if auth_subject != "sub-owner":
            raise AssertionError(auth_subject)
        return SimpleNamespace(user_id="user-owner")

    def _require_active_membership(self, user_id: str, group_id: str) -> None:
        self.membership = (user_id, group_id)

    def _require_app_capacity(self, group_id: str) -> None:
        self.capacity_group_id = group_id

    def _draft_source_key(self, group_id: str, app_id: str, revision: int) -> str:
        return f"draft/{group_id}/{app_id}/{revision}.zip"

    def _put_immutable_zip(self, **kwargs: object) -> str:
        self.put_count += 1
        return "version-1"

    def _source_manifest(self, **kwargs: object) -> dict[str, object]:
        return {"pk": {"S": "SOURCE"}, "sk": {"S": "REV#1"}}

    def _transact_put_new(self, items: list[dict[str, object]]) -> None:
        self.items = items

    def _delete_failed_write(self, *args: object) -> None:
        raise AssertionError("cleanup should not run")

    def _public_hosted_app(self, item: dict[str, object]) -> dict[str, object]:
        return {"created": True}


class HostedUploadAuthoringManifestTests(unittest.TestCase):
    def test_editor_contract_is_written_to_app_and_group_index(self) -> None:
        backend = FakeUploadBackend()
        create_uploaded_app(
            backend,
            "sub-owner",
            "2" * 32,
            "絵本メーカー",
            make_zip(
                {
                    "authoring": {
                        "edits": ["example/picture-book@1"],
                        "accepts": [],
                        "master_data_element_id": None,
                    }
                }
            ),
        )

        self.assertIsNotNone(backend.items)
        assert backend.items is not None
        self.assertEqual(len(backend.items), 3)
        for item in backend.items[:2]:
            self.assertEqual(item["edits_json"], {"S": '["example/picture-book@1"]'})
            self.assertEqual(item["accepts_json"], {"S": "[]"})
            self.assertEqual(item["master_data_element_id"], {"NULL": True})
        self.assertEqual(backend.put_count, 1)

    def test_player_contract_stores_master_target(self) -> None:
        backend = FakeUploadBackend()
        create_uploaded_app(
            backend,
            "sub-owner",
            "2" * 32,
            "絵本プレイヤー",
            make_zip(
                {
                    "authoring": {
                        "edits": [],
                        "accepts": ["example/picture-book@1"],
                        "master_data_element_id": "book-data",
                    }
                }
            ),
        )

        assert backend.items is not None
        for item in backend.items[:2]:
            self.assertEqual(item["edits_json"], {"S": "[]"})
            self.assertEqual(item["accepts_json"], {"S": '["example/picture-book@1"]'})
            self.assertEqual(item["master_data_element_id"], {"S": "book-data"})

    def test_invalid_manifest_fails_before_s3_or_metadata_writes(self) -> None:
        backend = FakeUploadBackend()
        with self.assertRaises(ApiProblem) as caught:
            create_uploaded_app(
                backend,
                "sub-owner",
                "2" * 32,
                "壊れたメーカー",
                make_zip(
                    {
                        "authoring": {
                            "edits": ["bad-format"],
                            "accepts": [],
                            "master_data_element_id": None,
                        }
                    }
                ),
            )
        self.assertEqual(caught.exception.error, "invalid_authoring_manifest")
        self.assertEqual(backend.put_count, 0)
        self.assertIsNone(backend.items)

    def test_no_manifest_keeps_ordinary_app_metadata_clean(self) -> None:
        backend = FakeUploadBackend()
        create_uploaded_app(
            backend,
            "sub-owner",
            "2" * 32,
            "普通のアプリ",
            make_zip(None),
        )

        assert backend.items is not None
        for item in backend.items[:2]:
            self.assertNotIn("edits_json", item)
            self.assertNotIn("accepts_json", item)
            self.assertNotIn("master_data_element_id", item)


if __name__ == "__main__":
    unittest.main()
