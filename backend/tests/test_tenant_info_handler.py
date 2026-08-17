from __future__ import annotations

import importlib
import json
import os
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))


def _event(method: str, path: str) -> dict[str, Any]:
    return {
        "rawPath": path,
        "requestContext": {"http": {"method": method}},
    }


def _load_handler(*, tenant_id: str = "a" * 32):
    sys.modules.pop("tenant_info_handler", None)
    with patch.dict(
        os.environ,
        {
            "TENANT_ID": tenant_id,
            "API_PROTOCOL_VERSION": "1",
            "ENVIRONMENT": "dev",
        },
        clear=True,
    ):
        return importlib.import_module("tenant_info_handler")


class TenantInfoHandlerTests(unittest.TestCase):
    def tearDown(self) -> None:
        sys.modules.pop("tenant_info_handler", None)

    def test_get_tenant_info_has_exact_public_schema(self) -> None:
        handler = _load_handler()
        response = handler.lambda_handler(_event("GET", "/tenant-info"), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["headers"]["cache-control"], "no-store")
        payload = json.loads(response["body"])
        self.assertEqual(
            payload,
            {
                "service": "minapp-tenant-api",
                "tenant_id": "a" * 32,
                "api_protocol_version": 1,
                "environment": "dev",
            },
        )

    def test_unknown_path_fails_closed(self) -> None:
        handler = _load_handler()
        response = handler.lambda_handler(_event("GET", "/health"), None)
        self.assertEqual(response["statusCode"], 404)

    def test_invalid_tenant_environment_fails_during_module_startup(self) -> None:
        sys.modules.pop("tenant_info_handler", None)
        with patch.dict(
            os.environ,
            {
                "TENANT_ID": "bad",
                "API_PROTOCOL_VERSION": "1",
                "ENVIRONMENT": "dev",
            },
            clear=True,
        ), self.assertRaises(RuntimeError):
            importlib.import_module("tenant_info_handler")


if __name__ == "__main__":
    unittest.main()
