from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from dev_server import MinAppDevHandler, validate_directory_descriptor  # noqa: E402


TENANT_ID = "0123456789abcdef0123456789abcdef"


def descriptor(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema_version": 1,
        "tenant_id": TENANT_ID,
        "display_name": "テスト教室",
        "api_base_url": "https://tenant.example.com/",
        "api_protocol_version": 1,
        "config_revision": 2,
        "valid_for_seconds": 86400,
    }
    value.update(overrides)
    return value


class ValidateDirectoryDescriptorTests(unittest.TestCase):
    def test_accepts_valid_descriptor_and_canonicalizes_api_url(self) -> None:
        actual = validate_directory_descriptor(
            descriptor(),
            expected_tenant_id=TENANT_ID,
        )

        self.assertEqual(actual["tenant_id"], TENANT_ID)
        self.assertEqual(actual["display_name"], "テスト教室")
        self.assertEqual(actual["api_base_url"], "https://tenant.example.com")
        self.assertEqual(actual["config_revision"], 2)

    def test_rejects_descriptor_for_different_tenant(self) -> None:
        with self.assertRaisesRegex(ValueError, "different tenant_id"):
            validate_directory_descriptor(
                descriptor(tenant_id="fedcba9876543210fedcba9876543210"),
                expected_tenant_id=TENANT_ID,
            )

    def test_rejects_unknown_descriptor_field(self) -> None:
        payload = descriptor()
        payload["unexpected"] = "value"

        with self.assertRaisesRegex(ValueError, "schema is invalid"):
            validate_directory_descriptor(payload, expected_tenant_id=TENANT_ID)

    def test_rejects_tenant_api_url_with_path(self) -> None:
        with self.assertRaisesRegex(ValueError, "path must be empty or /"):
            validate_directory_descriptor(
                descriptor(api_base_url="https://tenant.example.com/not-allowed"),
                expected_tenant_id=TENANT_ID,
            )

    def test_rejects_boolean_protocol_version(self) -> None:
        with self.assertRaisesRegex(ValueError, "api_protocol_version"):
            validate_directory_descriptor(
                descriptor(api_protocol_version=True),
                expected_tenant_id=TENANT_ID,
            )


class TenantRoutingCookieTests(unittest.TestCase):
    def test_selected_tenant_cookie_is_http_only_and_same_site_strict(self) -> None:
        cookie = MinAppDevHandler._tenant_cookie(TENANT_ID)

        self.assertIn(f"minapp_tenant_id={TENANT_ID}", cookie)
        self.assertIn("HttpOnly", cookie)
        self.assertIn("SameSite=Strict", cookie)
        self.assertIn("Path=/", cookie)

    def test_clear_cookie_expires_selected_tenant(self) -> None:
        cookie = MinAppDevHandler._clear_tenant_cookie()

        self.assertIn("minapp_tenant_id=", cookie)
        self.assertIn("Max-Age=0", cookie)
        self.assertIn("HttpOnly", cookie)
        self.assertIn("SameSite=Strict", cookie)


if __name__ == "__main__":
    unittest.main()
