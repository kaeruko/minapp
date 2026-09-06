from __future__ import annotations

import io
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from zip_upload_normalization import normalize_uploaded_zip  # noqa: E402


def _zip(entries: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return output.getvalue()


class ZipUploadNormalizationTests(unittest.TestCase):
    def test_root_index_zip_is_returned_unchanged(self) -> None:
        original = _zip({"index.html": b"<h1>ok</h1>", "app.js": b"ok"})
        normalized, files = normalize_uploaded_zip(original)
        self.assertIs(normalized, original)
        self.assertEqual(files, ["app.js", "index.html"])

    def test_single_top_level_folder_is_unwrapped(self) -> None:
        original = _zip(
            {
                "minappchi/index.html": b"<h1>minappchi</h1>",
                "minappchi/app.js": b"console.log('ok')",
                "minappchi/images/icon.png": b"png",
            }
        )
        normalized, files = normalize_uploaded_zip(original)

        self.assertEqual(files, ["app.js", "images/icon.png", "index.html"])
        with zipfile.ZipFile(io.BytesIO(normalized)) as archive:
            self.assertEqual(set(archive.namelist()), set(files))
            self.assertEqual(archive.read("index.html"), b"<h1>minappchi</h1>")

    def test_finder_metadata_is_removed_before_unwrapping(self) -> None:
        original = _zip(
            {
                "minappchi/index.html": b"<h1>minappchi</h1>",
                "minappchi/.DS_Store": b"finder",
                "__MACOSX/minappchi/._index.html": b"resource-fork",
            }
        )
        normalized, files = normalize_uploaded_zip(original)

        self.assertEqual(files, ["index.html"])
        with zipfile.ZipFile(io.BytesIO(normalized)) as archive:
            self.assertEqual(archive.namelist(), ["index.html"])
            self.assertEqual(archive.read("index.html"), b"<h1>minappchi</h1>")

    def test_two_top_level_folders_remain_invalid(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            normalize_uploaded_zip(
                _zip(
                    {
                        "app/index.html": b"ok",
                        "other/app.js": b"no",
                    }
                )
            )
        self.assertEqual(context.exception.error, "index_missing")

    def test_two_extra_directory_levels_remain_invalid(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            normalize_uploaded_zip(_zip({"outer/inner/index.html": b"no"}))
        self.assertEqual(context.exception.error, "index_missing")

    def test_existing_validation_errors_are_not_bypassed(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            normalize_uploaded_zip(
                _zip(
                    {
                        "app/index.html": b"ok",
                        "../secret.txt": b"no",
                    }
                )
            )
        self.assertEqual(context.exception.error, "invalid_zip_path")

    def test_unknown_unsupported_file_is_not_silently_removed(self) -> None:
        with self.assertRaises(ApiProblem) as context:
            normalize_uploaded_zip(
                _zip(
                    {
                        "app/index.html": b"ok",
                        "app/program.exe": b"no",
                    }
                )
            )
        self.assertEqual(context.exception.error, "unsupported_file_type")


if __name__ == "__main__":
    unittest.main()
