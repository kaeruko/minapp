from __future__ import annotations

import sys
import unittest
from pathlib import Path

DIRECTORY_SRC = Path(__file__).resolve().parents[1] / "src"
if str(DIRECTORY_SRC) not in sys.path:
    sys.path.insert(0, str(DIRECTORY_SRC))

from directory_core import (  # noqa: E402
    DirectoryProblem,
    descriptor_from_tenant,
    generate_classroom_code,
    hash_classroom_code,
    normalize_classroom_code,
    strict_json_object,
    validate_api_base_url,
)


class DirectoryCoreTests(unittest.TestCase):
    def test_code_normalization_is_case_insensitive_and_hyphen_optional(self) -> None:
        self.assertEqual(normalize_classroom_code("7k2m-4q9p-w6tx"), "7K2M4Q9PW6TX")
        self.assertEqual(normalize_classroom_code("7K2M4Q9PW6TX"), "7K2M4Q9PW6TX")
        self.assertEqual(
            hash_classroom_code("7K2M4Q9PW6TX"),
            hash_classroom_code(normalize_classroom_code("7k2m-4q9p-w6tx")),
        )

    def test_generated_code_is_normalizable(self) -> None:
        code = generate_classroom_code()
        self.assertEqual(len(code), 14)
        self.assertEqual(code[4], "-")
        self.assertEqual(code[9], "-")
        self.assertEqual(len(normalize_classroom_code(code)), 12)

    def test_invalid_codes_fail_without_fuzzy_lookup(self) -> None:
        for value in (
            "",
            "7K2M-4Q9P-W6T",
            "7K2M-4Q9P-W6TX-extra",
            "7K2M 4Q9P W6TX",
            "0K2M-4Q9P-W6TX",
            "IK2M-4Q9P-W6TX",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                normalize_classroom_code(value)

    def test_endpoint_validation_accepts_only_public_https_origin(self) -> None:
        self.assertEqual(
            validate_api_base_url("https://abc.execute-api.us-west-2.amazonaws.com/"),
            "https://abc.execute-api.us-west-2.amazonaws.com",
        )
        invalid = (
            "http://example.com",
            "https://localhost",
            "https://api.local",
            "https://api.internal",
            "https://127.0.0.1",
            "https://10.0.0.1",
            "https://example.com:8443",
            "https://user@example.com",
            "https://example.com/path",
            "https://example.com?x=1",
            "https://example.com#fragment",
            "https://singlelabel",
        )
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_api_base_url(value)

    def test_descriptor_is_exact_and_has_ttl(self) -> None:
        tenant = {
            "schema_version": 1,
            "tenant_id": "a" * 32,
            "display_name": "Test School",
            "status": "active",
            "api_base_url": "https://tenant.example.com/",
            "api_protocol_version": 1,
            "config_revision": 3,
            "internal_only": "not exposed",
        }
        self.assertEqual(
            descriptor_from_tenant(tenant, valid_for_seconds=86400),
            {
                "schema_version": 1,
                "tenant_id": "a" * 32,
                "display_name": "Test School",
                "api_base_url": "https://tenant.example.com",
                "api_protocol_version": 1,
                "config_revision": 3,
                "valid_for_seconds": 86400,
            },
        )

    def test_unknown_stored_schema_version_fails_explicitly(self) -> None:
        with self.assertRaises(DirectoryProblem) as caught:
            descriptor_from_tenant(
                {
                    "schema_version": 2,
                    "tenant_id": "a" * 32,
                },
                valid_for_seconds=60,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.code, "incompatible_tenant_config")

    def test_strict_json_rejects_unknown_fields(self) -> None:
        with self.assertRaises(DirectoryProblem) as caught:
            strict_json_object(
                '{"code":"7K2M-4Q9P-W6TX","schema_version":2}',
                expected_fields={"code"},
            )
        self.assertEqual(caught.exception.code, "invalid_request")


if __name__ == "__main__":
    unittest.main()
