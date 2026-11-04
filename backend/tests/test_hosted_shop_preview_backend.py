from __future__ import annotations

import hashlib
import io
import json
import sys
import unittest
import zipfile
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_shop_backend import HostedShopBackend  # noqa: E402

APP_ID = "a" * 32


class PreviewHarness(HostedShopBackend):
    def __init__(self) -> None:
        self.listed = True
        self.version = 3
        self.files = {"index.html": b"<html>published</html>", "assets/app.js": b"run();"}
        data = io.BytesIO()
        with zipfile.ZipFile(data, mode="w") as archive:
            for path, value in self.files.items():
                archive.writestr(path, value)
        self.published_zip = data.getvalue()
        self.sha256 = hashlib.sha256(self.published_zip).hexdigest()
        self._published_bucket = "published-test-bucket"
        self.read_count = 0

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None:
        if pk != f"APP#{APP_ID}" or sk != "META":
            return None
        return {
            "entity": {"S": "hosted_app"},
            "shop_visibility": {"S": "listed" if self.listed else "unlisted"},
            "app_id": {"S": APP_ID},
            "published_version": {"N": str(self.version)},
            "published_key": {"S": "published/test.zip"},
            "published_sha256": {"S": self.sha256},
            "published_at": {"S": "2026-09-13T02:00:00Z"},
            "published_files_json": {"S": json.dumps(list(self.files))},
        }

    def _read_zip_object(
        self, *, bucket: str, key: str, expected_sha256: str | None = None
    ) -> tuple[bytes, list[str], str]:
        self.read_count += 1
        if bucket != self._published_bucket or key != "published/test.zip":
            raise AssertionError("unexpected published ZIP object")
        if expected_sha256 != self.sha256:
            raise AssertionError("checksum validation argument missing")
        return self.published_zip, list(self.files), self.sha256


class GuestPreviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = PreviewHarness()

    def test_guest_gets_same_published_html_and_asset_bytes(self) -> None:
        html, content_type = self.backend.get_shop_preview_file(APP_ID, "3", "index.html")
        self.assertEqual(html, self.backend.files["index.html"])
        self.assertEqual(content_type, "text/html; charset=utf-8")
        js, _ = self.backend.get_shop_preview_file(APP_ID, "3", "assets/app.js")
        self.assertEqual(js, self.backend.files["assets/app.js"])
        self.assertEqual(self.backend.read_count, 2)

    def test_unlisted_work_cannot_be_previewed(self) -> None:
        self.backend.listed = False
        with self.assertRaises(ApiProblem) as failure:
            self.backend.get_shop_preview_file(APP_ID, "3", "index.html")
        self.assertEqual(failure.exception.status_code, 404)
        self.assertEqual(self.backend.read_count, 0)

    def test_stale_version_is_rejected(self) -> None:
        with self.assertRaises(ApiProblem) as failure:
            self.backend.get_shop_preview_file(APP_ID, "2", "index.html")
        self.assertEqual(failure.exception.status_code, 409)
        self.assertEqual(self.backend.read_count, 0)

    def test_missing_file_and_traversal_are_rejected(self) -> None:
        for path in ("missing.html", "../index.html", "/index.html"):
            with self.subTest(path=path), self.assertRaises(ApiProblem):
                self.backend.get_shop_preview_file(APP_ID, "3", path)
        self.assertEqual(self.backend.read_count, 0)


if __name__ == "__main__":
    unittest.main()
