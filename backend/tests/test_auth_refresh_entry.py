from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import abuse_entry  # noqa: E402


def _event(body: dict[str, object]) -> dict[str, object]:
    return {
        "rawPath": "/auth/refresh",
        "requestContext": {"http": {"method": "POST", "sourceIp": "203.0.113.10"}},
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


class AuthRefreshEntryTests(unittest.TestCase):
    def test_refresh_returns_new_access_token(self) -> None:
        expected = {
            "state": "authenticated",
            "access_token": "new-access",
            "token_type": "Bearer",
            "expires_in": 86400,
        }
        with patch.object(abuse_entry, "refresh_access_token", return_value=expected) as refresh:
            response = abuse_entry.api_lambda_handler(
                _event({"refresh_token": "refresh-token"}),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), expected)
        refresh.assert_called_once_with("refresh-token")

    def test_refresh_rejects_unknown_fields(self) -> None:
        response = abuse_entry.api_lambda_handler(
            _event({"refresh_token": "refresh-token", "unexpected": True}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")

    def test_refresh_rejects_empty_token(self) -> None:
        response = abuse_entry.api_lambda_handler(
            _event({"refresh_token": ""}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(json.loads(response["body"])["error"], "invalid_request")


if __name__ == "__main__":
    unittest.main()
