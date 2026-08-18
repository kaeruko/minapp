from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

DIRECTORY_SRC = Path(__file__).resolve().parents[1] / "src"
if str(DIRECTORY_SRC) not in sys.path:
    sys.path.insert(0, str(DIRECTORY_SRC))

import directory_handler  # noqa: E402
from directory_core import hash_classroom_code, normalize_classroom_code  # noqa: E402


CODE = "7K2M-4Q9P-W6TX"
TENANT_ID = "a" * 32


def _event(method: str, path: str, *, body: str | None = None) -> dict[str, Any]:
    return {
        "rawPath": path,
        "rawQueryString": "",
        "headers": {"content-type": "application/json"},
        "body": body,
        "isBase64Encoded": False,
        "requestContext": {
            "http": {
                "method": method,
                "sourceIp": "203.0.113.25",
            }
        },
    }


class FakeStore:
    def __init__(self) -> None:
        self.allowed = True
        self.mapping = {
            "tenant_id": TENANT_ID,
            "status": "active",
        }
        self.tenant = {
            "schema_version": 1,
            "tenant_id": TENANT_ID,
            "display_name": "Test School",
            "status": "active",
            "api_base_url": "https://tenant.example.com",
            "api_protocol_version": 1,
            "config_revision": 2,
        }
        self.last_subject_hash: str | None = None

    def now_epoch(self) -> int:
        return 1_700_000_000

    def consume_rate_limit(self, subject_hash: str, **kwargs: Any) -> bool:
        self.last_subject_hash = subject_hash
        return self.allowed

    def get_code_mapping(self, code_hash: str) -> dict[str, Any] | None:
        expected = hash_classroom_code(normalize_classroom_code(CODE))
        return self.mapping if code_hash == expected else None

    def get_tenant(self, tenant_id: str) -> dict[str, Any] | None:
        return self.tenant if tenant_id == TENANT_ID else None


class DirectoryHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = FakeStore()
        self.env = patch.dict(
            os.environ,
            {
                "DESCRIPTOR_TTL_SECONDS": "86400",
                "RATE_LIMIT_WINDOW_SECONDS": "60",
                "RATE_LIMIT_REQUESTS": "60",
            },
            clear=False,
        )
        self.env.start()
        self.store_patch = patch.object(directory_handler, "_load_store", return_value=self.store)
        self.store_patch.start()

    def tearDown(self) -> None:
        self.store_patch.stop()
        self.env.stop()

    def test_resolve_returns_exact_descriptor(self) -> None:
        response = directory_handler.lambda_handler(
            _event("POST", "/v1/classrooms/resolve", body=json.dumps({"code": CODE})),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            json.loads(response["body"]),
            {
                "schema_version": 1,
                "tenant_id": TENANT_ID,
                "display_name": "Test School",
                "api_base_url": "https://tenant.example.com",
                "api_protocol_version": 1,
                "config_revision": 2,
                "valid_for_seconds": 86400,
            },
        )
        self.assertIsNotNone(self.store.last_subject_hash)
        self.assertNotEqual(self.store.last_subject_hash, "203.0.113.25")

    def test_unknown_request_field_is_rejected(self) -> None:
        response = directory_handler.lambda_handler(
            _event(
                "POST",
                "/v1/classrooms/resolve",
                body=json.dumps({"code": CODE, "schema_version": 2}),
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")

    def test_invalid_code_has_typed_error(self) -> None:
        response = directory_handler.lambda_handler(
            _event("POST", "/v1/classrooms/resolve", body=json.dumps({"code": "bad"})),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_classroom_code")

    def test_rotated_code_is_not_resolved(self) -> None:
        self.store.mapping["status"] = "rotated"
        response = directory_handler.lambda_handler(
            _event("POST", "/v1/classrooms/resolve", body=json.dumps({"code": CODE})),
            None,
        )
        self.assertEqual(response["statusCode"], 404)
        self.assertEqual(json.loads(response["body"])["error"], "classroom_not_found")

    def test_inactive_tenant_returns_gone(self) -> None:
        self.store.tenant["status"] = "inactive"
        response = directory_handler.lambda_handler(
            _event("GET", f"/v1/tenants/{TENANT_ID}"),
            None,
        )
        self.assertEqual(response["statusCode"], 410)
        self.assertEqual(json.loads(response["body"])["error"], "classroom_inactive")

    def test_pending_tenant_is_not_publicly_discoverable(self) -> None:
        self.store.tenant["status"] = "pending"
        response = directory_handler.lambda_handler(
            _event("GET", f"/v1/tenants/{TENANT_ID}"),
            None,
        )
        self.assertEqual(response["statusCode"], 404)
        self.assertEqual(json.loads(response["body"])["error"], "classroom_not_found")

    def test_unknown_stored_schema_returns_conflict(self) -> None:
        self.store.tenant["schema_version"] = 99
        response = directory_handler.lambda_handler(
            _event("GET", f"/v1/tenants/{TENANT_ID}"),
            None,
        )
        self.assertEqual(response["statusCode"], 409)
        self.assertEqual(json.loads(response["body"])["error"], "incompatible_tenant_config")

    def test_rate_limit_returns_typed_429(self) -> None:
        self.store.allowed = False
        response = directory_handler.lambda_handler(
            _event("GET", f"/v1/tenants/{TENANT_ID}"),
            None,
        )
        self.assertEqual(response["statusCode"], 429)
        self.assertEqual(json.loads(response["body"])["error"], "rate_limited")

    def test_raw_classroom_code_is_absent_from_application_logs(self) -> None:
        with self.assertLogs(directory_handler._LOGGER, level="INFO") as captured:
            response = directory_handler.lambda_handler(
                _event("POST", "/v1/classrooms/resolve", body=json.dumps({"code": CODE})),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        self.assertNotIn(CODE, "\n".join(captured.output))
        self.assertNotIn(normalize_classroom_code(CODE), "\n".join(captured.output))


if __name__ == "__main__":
    unittest.main()
