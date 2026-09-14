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
from hosted_authoring_manifest import read_authoring_manifest  # noqa: E402


def app_zip(manifest: object | None = None, *, raw_manifest: bytes | None = None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", "<!doctype html><title>test</title>")
        if raw_manifest is not None:
            archive.writestr("minapp.json", raw_manifest)
        elif manifest is not None:
            archive.writestr(
                "minapp.json",
                json.dumps(manifest, ensure_ascii=False, separators=(",", ":")),
            )
    return buffer.getvalue()


class HostedAuthoringManifestTests(unittest.TestCase):
    def assert_invalid(self, zip_bytes: bytes) -> ApiProblem:
        with self.assertRaises(ApiProblem) as caught:
            read_authoring_manifest(zip_bytes)
        self.assertEqual(caught.exception.status_code, 400)
        self.assertEqual(caught.exception.error, "invalid_authoring_manifest")
        return caught.exception

    def test_missing_manifest_is_an_ordinary_app(self) -> None:
        self.assertIsNone(read_authoring_manifest(app_zip()))

    def test_editor_manifest(self) -> None:
        contract = read_authoring_manifest(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/picture-book@1"],
                        "accepts": [],
                        "master_data_element_id": None,
                    }
                }
            )
        )
        self.assertIsNotNone(contract)
        assert contract is not None
        self.assertEqual(contract.edits, ("example/picture-book@1",))
        self.assertEqual(contract.accepts, ())
        self.assertIsNone(contract.master_data_element_id)

    def test_player_manifest(self) -> None:
        contract = read_authoring_manifest(
            app_zip(
                {
                    "authoring": {
                        "edits": [],
                        "accepts": ["example/picture-book@1"],
                        "master_data_element_id": "book-data",
                    }
                }
            )
        )
        self.assertIsNotNone(contract)
        assert contract is not None
        self.assertEqual(contract.edits, ())
        self.assertEqual(contract.accepts, ("example/picture-book@1",))
        self.assertEqual(contract.master_data_element_id, "book-data")

    def test_editor_and_player_contract_is_allowed(self) -> None:
        contract = read_authoring_manifest(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/picture-book@1"],
                        "accepts": ["example/picture-book@1"],
                        "master_data_element_id": "book-data",
                    }
                }
            )
        )
        self.assertIsNotNone(contract)

    def test_invalid_json_fails_instead_of_falling_back(self) -> None:
        self.assert_invalid(app_zip(raw_manifest=b"{not json"))

    def test_non_utf8_manifest_is_rejected(self) -> None:
        self.assert_invalid(app_zip(raw_manifest=b"\xff\xfe"))

    def test_unknown_top_level_field_is_rejected(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/book@1"],
                        "accepts": [],
                        "master_data_element_id": None,
                    },
                    "extra": True,
                }
            )
        )

    def test_unknown_authoring_field_is_rejected(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/book@1"],
                        "accepts": [],
                        "master_data_element_id": None,
                        "extra": True,
                    }
                }
            )
        )

    def test_duplicate_format_is_rejected(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/book@1", "example/book@1"],
                        "accepts": [],
                        "master_data_element_id": None,
                    }
                }
            )
        )

    def test_invalid_content_format_is_rejected(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": ["not-versioned"],
                        "accepts": [],
                        "master_data_element_id": None,
                    }
                }
            )
        )

    def test_empty_contract_is_rejected(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": [],
                        "accepts": [],
                        "master_data_element_id": None,
                    }
                }
            )
        )

    def test_player_requires_master_data_element_id(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": [],
                        "accepts": ["example/book@1"],
                        "master_data_element_id": None,
                    }
                }
            )
        )

    def test_editor_without_accepts_requires_null_master_target(self) -> None:
        self.assert_invalid(
            app_zip(
                {
                    "authoring": {
                        "edits": ["example/book@1"],
                        "accepts": [],
                        "master_data_element_id": "book-data",
                    }
                }
            )
        )


if __name__ == "__main__":
    unittest.main()
