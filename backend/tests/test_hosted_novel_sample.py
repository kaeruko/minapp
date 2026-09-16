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


if __name__ == "__main__":
    unittest.main()
