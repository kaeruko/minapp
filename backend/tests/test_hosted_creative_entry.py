from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_entry  # noqa: E402
from hosted_catalog_backend import BUILTIN_TEMPLATES  # noqa: E402


class HostedCreativeEntryTests(unittest.TestCase):
    def test_normal_hosted_route_registers_novel_before_delegation(self) -> None:
        original = dict(BUILTIN_TEMPLATES)
        BUILTIN_TEMPLATES.pop("novel-starter", None)
        try:
            with patch.object(
                hosted_entry.hosted_handler,
                "lambda_handler",
                return_value={"statusCode": 200, "body": "ok"},
            ) as delegated:
                response = hosted_entry.lambda_handler(
                    {
                        "rawPath": "/hosted/builtins",
                        "requestContext": {"http": {"method": "GET"}},
                        "headers": {},
                    },
                    None,
                )

            self.assertEqual(response["statusCode"], 200)
            self.assertIn("novel-starter", BUILTIN_TEMPLATES)
            self.assertEqual(BUILTIN_TEMPLATES["novel-starter"]["title"], "ひみつの放課後")
            delegated.assert_called_once()
        finally:
            BUILTIN_TEMPLATES.clear()
            BUILTIN_TEMPLATES.update(original)


if __name__ == "__main__":
    unittest.main()
