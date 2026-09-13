from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from hosted_shop_backend import (
    _shop_download_content_disposition,
    _shop_download_filename,
)


class HostedShopDownloadFilenameTests(unittest.TestCase):
    def test_keeps_japanese_title_for_user_visible_filename(self) -> None:
        filename = _shop_download_filename("おえかき", "ecb3cb6a08e05305668a952cbdae435b")
        self.assertEqual(filename, "おえかき.zip")

        disposition = _shop_download_content_disposition(
            filename,
            "ecb3cb6a08e05305668a952cbdae435b",
        )
        self.assertIn('filename="minapp-ecb3cb6a08e05305668a952cbdae435b.zip"', disposition)
        self.assertIn("filename*=UTF-8''%E3%81%8A%E3%81%88%E3%81%8B%E3%81%8D.zip", disposition)

    def test_replaces_filesystem_unsafe_title_characters(self) -> None:
        filename = _shop_download_filename('猫/犬:ゲーム?*"<>|', "abcdef0123456789")
        self.assertEqual(filename, "猫_犬_ゲーム_______.zip")

    def test_uses_safe_fallback_when_title_becomes_empty(self) -> None:
        filename = _shop_download_filename('... ', "abcdef0123456789")
        self.assertEqual(filename, "minapp-abcdef01.zip")


if __name__ == "__main__":
    unittest.main()
