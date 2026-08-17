from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from handler import lambda_handler  # noqa: E402


class HandlerTests(unittest.TestCase):
    def test_health(self) -> None:
        response = lambda_handler(
            {
                "rawPath": "/health",
                "requestContext": {"http": {"method": "GET"}},
            },
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["service"], "minapp-api")
        self.assertEqual(payload["status"], "ok")

    def test_unknown_route_is_404(self) -> None:
        response = lambda_handler(
            {
                "rawPath": "/unknown",
                "requestContext": {"http": {"method": "GET"}},
            },
            None,
        )

        self.assertEqual(response["statusCode"], 404)

    def test_malformed_event_fails_fast(self) -> None:
        with self.assertRaisesRegex(ValueError, "requestContext"):
            lambda_handler({"rawPath": "/health"}, None)


if __name__ == "__main__":
    unittest.main()
