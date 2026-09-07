from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from app_zip import content_type as _content_type, safe_zip_paths as _safe_zip_paths  # noqa: E402
from errors import ApiProblem  # noqa: E402


def _zip(entries: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return buffer.getvalue()


class ZipValidationTests(unittest.TestCase):
    def test_accepts_static_web_app(self) -> None:
        data = _zip(
            {
                "index.html": b"<!doctype html><script src='app.js'></script>",
                "app.js": b"document.body.dataset.ready = 'yes';",
                "images/icon.png": b"png",
            }
        )
        self.assertEqual(
            _safe_zip_paths(data),
            ["app.js", "images/icon.png", "index.html"],
        )

    def test_accepts_novel_audio_assets(self) -> None:
        data = _zip(
            {
                "index.html": b"ok",
                "audio/bgm.mp3": b"mp3",
                "audio/voice.m4a": b"m4a",
                "audio/ambient.ogg": b"ogg",
                "audio/click.wav": b"wav",
            }
        )
        self.assertEqual(
            _safe_zip_paths(data),
            [
                "audio/ambient.ogg",
                "audio/bgm.mp3",
                "audio/click.wav",
                "audio/voice.m4a",
                "index.html",
            ],
        )

    def test_uses_explicit_audio_content_types(self) -> None:
        self.assertEqual(_content_type("audio/bgm.mp3"), "audio/mpeg")
        self.assertEqual(_content_type("audio/voice.m4a"), "audio/mp4")
        self.assertEqual(_content_type("audio/ambient.ogg"), "audio/ogg")
        self.assertEqual(_content_type("audio/click.wav"), "audio/wav")

    def test_requires_root_index_html(self) -> None:
        with self.assertRaisesRegex(ApiProblem, "index.html"):
            _safe_zip_paths(_zip({"site/index.html": b"hello"}))

    def test_rejects_path_traversal(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            _safe_zip_paths(_zip({"index.html": b"ok", "../secret.txt": b"no"}))
        self.assertEqual(context.exception.error, "invalid_zip_path")

    def test_rejects_executable_file_type(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            _safe_zip_paths(_zip({"index.html": b"ok", "run.exe": b"no"}))
        self.assertEqual(context.exception.error, "unsupported_file_type")


if __name__ == "__main__":
    unittest.main()
