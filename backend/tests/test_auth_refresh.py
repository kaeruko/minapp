from __future__ import annotations

import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import auth_refresh  # noqa: E402
from errors import ApiProblem  # noqa: E402


class FakeAwsError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeCognito:
    def __init__(self, response: dict[str, object] | None = None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error
        self.calls: list[dict[str, object]] = []

    def initiate_auth(self, **kwargs: object) -> dict[str, object]:
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        if self.response is None:
            raise AssertionError("Fake Cognito response was not configured")
        return self.response


class AuthRefreshTests(unittest.TestCase):
    def test_refresh_exchanges_refresh_token(self) -> None:
        cognito = FakeCognito(
            response={
                "AuthenticationResult": {
                    "AccessToken": "new-access",
                    "TokenType": "Bearer",
                    "ExpiresIn": 86400,
                }
            }
        )
        fake_boto3 = types.SimpleNamespace(client=lambda service: cognito)
        with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
            os.environ,
            {"USER_POOL_CLIENT_ID": "client-id"},
            clear=False,
        ):
            result = auth_refresh.refresh_access_token("refresh-token")

        self.assertEqual(
            result,
            {
                "state": "authenticated",
                "access_token": "new-access",
                "token_type": "Bearer",
                "expires_in": 86400,
            },
        )
        self.assertEqual(
            cognito.calls,
            [
                {
                    "ClientId": "client-id",
                    "AuthFlow": "REFRESH_TOKEN_AUTH",
                    "AuthParameters": {"REFRESH_TOKEN": "refresh-token"},
                }
            ],
        )

    def test_invalid_refresh_token_becomes_401(self) -> None:
        cognito = FakeCognito(error=FakeAwsError("NotAuthorizedException"))
        fake_boto3 = types.SimpleNamespace(client=lambda service: cognito)
        with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
            os.environ,
            {"USER_POOL_CLIENT_ID": "client-id"},
            clear=False,
        ):
            with self.assertRaises(ApiProblem) as raised:
                auth_refresh.refresh_access_token("expired-refresh-token")

        self.assertEqual(raised.exception.status_code, 401)
        self.assertEqual(raised.exception.error, "invalid_refresh_token")


if __name__ == "__main__":
    unittest.main()
