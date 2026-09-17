from __future__ import annotations

import io
import json
import sys
import unittest
import zipfile
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_package_manifest import read_package_manifest  # noqa: E402


def make_zip(manifest: object | None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", "<!doctype html><title>test</title>")
        if manifest is not None:
            archive.writestr(
                "minapp-package.json",
                json.dumps(manifest, separators=(",", ":")),
            )
    return buffer.getvalue()


class HostedPackageManifestTests(unittest.TestCase):
    def test_missing_manifest_means_legacy_zip(self) -> None:
        self.assertIsNone(read_package_manifest(make_zip(None)))

    def test_valid_manifest_returns_stable_package_id(self) -> None:
        package_id = "0123456789abcdef0123456789abcdef"
        manifest = read_package_manifest(
            make_zip({"schema_version": 1, "package_id": package_id})
        )
        self.assertIsNotNone(manifest)
        assert manifest is not None
        self.assertEqual(manifest.package_id, package_id)

    def test_invalid_package_id_is_rejected(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            read_package_manifest(
                make_zip({"schema_version": 1, "package_id": "NOT-A-VALID-ID"})
            )
        self.assertEqual(caught.exception.error, "invalid_package_manifest")

    def test_unknown_manifest_fields_are_rejected(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            read_package_manifest(
                make_zip(
                    {
                        "schema_version": 1,
                        "package_id": "0123456789abcdef0123456789abcdef",
                        "name": "must-not-be-here",
                    }
                )
            )
        self.assertEqual(caught.exception.error, "invalid_package_manifest")

    def test_unsupported_schema_version_is_rejected(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            read_package_manifest(
                make_zip(
                    {
                        "schema_version": 2,
                        "package_id": "0123456789abcdef0123456789abcdef",
                    }
                )
            )
        self.assertEqual(caught.exception.error, "invalid_package_manifest")


if __name__ == "__main__":
    unittest.main()
