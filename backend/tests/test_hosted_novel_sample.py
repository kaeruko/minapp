from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_novel_sample import (  # noqa: E402
    NOVEL_SAMPLE_SOURCE_KEY,
    _sample_asset_bytes,
    hydrate_novel_sample_project,
    novel_sample_document,
)

_PNG = b"\x89PNG\r\n\x1a\n"


class _FakeS3:
    def __init__(self, archive_bytes: bytes) -> None:
        self.archive_bytes = archive_bytes

    def get_object(self, *, Bucket: str, Key: str) -> dict[str, object]:
        if Bucket != "uploads":
            raise AssertionError(f"unexpected bucket: {Bucket}")
        if Key != NOVEL_SAMPLE_SOURCE_KEY:
            raise AssertionError(f"unexpected key: {Key}")
        return {"Body": io.BytesIO(self.archive_bytes)}


class _Backend:
    def __init__(self, archive_bytes: bytes) -> None:
        self._upload_bucket = "uploads"
        self._s3 = _FakeS3(archive_bytes)

    def _read_zip_object(self, **_: object) -> object:
        raise AssertionError("Novel sample assets must not use the 2MB app ZIP reader")


class HostedNovelSampleArchiveTests(unittest.TestCase):
    def test_sample_archive_can_exceed_app_zip_limit(self) -> None:
        classroom = _PNG + b"x" * (2 * 1024 * 1024 + 128 * 1024)
        rooftop = _PNG + b"rooftop"
        ren = _PNG + b"ren"
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("bg_classroom.png", classroom)
            archive.writestr("bg_rooftop.png", rooftop)
            archive.writestr("ren_normal.png", ren)
        archive_bytes = buffer.getvalue()
        self.assertGreater(len(archive_bytes), 2 * 1024 * 1024)

        assets = _sample_asset_bytes(_Backend(archive_bytes))

        self.assertEqual(assets["assets/sample/bg_classroom.png"], classroom)
        self.assertEqual(assets["assets/sample/bg_rooftop.png"], rooftop)
        self.assertEqual(assets["assets/sample/ren_normal.png"], ren)


class HostedNovelSampleOrderTests(unittest.TestCase):
    def test_sample_document_has_explicit_scene_order(self) -> None:
        document = novel_sample_document()
        self.assertEqual(
            document["scene_order"],
            ["start", "rooftop", "together", "photo", "leave"],
        )
        self.assertEqual(document["start_scene"], document["scene_order"][0])

    def test_hydration_migrates_untouched_sample_without_scene_order(self) -> None:
        current_document = novel_sample_document()
        current_document.pop("scene_order")
        saved: dict[str, object] = {}

        class MigrationBackend:
            def load_authoring_project(
                self,
                auth_subject: str,
                content_id: str,
            ) -> dict[str, object]:
                self._assert_scope(auth_subject, content_id)
                return {
                    "content_id": content_id,
                    "group_id": "2" * 32,
                    "content_format": "minapp/novel@1",
                    "status": "draft",
                    "draft_revision": 2,
                    "assets": [],
                    "created_at": "2026-09-16T01:00:00Z",
                    "updated_at": "2026-09-16T01:00:00Z",
                    "document": current_document,
                }

            def save_authoring_document(
                self,
                auth_subject: str,
                content_id: str,
                *,
                expected_revision: int,
                document: dict[str, object],
            ) -> dict[str, object]:
                self._assert_scope(auth_subject, content_id)
                if expected_revision != 2:
                    raise AssertionError(f"unexpected revision: {expected_revision}")
                saved["document"] = document
                return {
                    "content_id": content_id,
                    "group_id": "2" * 32,
                    "content_format": "minapp/novel@1",
                    "status": "draft",
                    "draft_revision": 3,
                    "assets": [],
                    "created_at": "2026-09-16T01:00:00Z",
                    "updated_at": "2026-09-30T14:00:00Z",
                }

            @staticmethod
            def _assert_scope(auth_subject: str, content_id: str) -> None:
                if auth_subject != "owner" or content_id != "6" * 32:
                    raise AssertionError("unexpected project scope")

        result = hydrate_novel_sample_project(
            MigrationBackend(),
            "owner",
            "6" * 32,
        )

        self.assertEqual(result["draft_revision"], 3)
        self.assertEqual(
            saved["document"]["scene_order"],  # type: ignore[index]
            ["start", "rooftop", "together", "photo", "leave"],
        )


if __name__ == "__main__":
    unittest.main()
