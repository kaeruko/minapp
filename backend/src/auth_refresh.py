from __future__ import annotations

from typing import Any

from aws_backend import _aws_error_code, _required_env
from errors import ApiProblem


def refresh_access_token(refresh_token: str) -> dict[str, Any]:
    if not isinstance(refresh_token, str) or not refresh_token:
        raise TypeError("refresh_token must be a non-empty string")

    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError(
            "boto3 is required outside the AWS Lambda runtime. "
            "Install the development requirements explicitly."
        ) from exc

    cognito = boto3.client("cognito-idp")
    try:
        response = cognito.initiate_auth(
            ClientId=_required_env("USER_POOL_CLIENT_ID"),
            AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={"REFRESH_TOKEN": refresh_token},
        )
    except Exception as exc:
        if _aws_error_code(exc) == "NotAuthorizedException":
            raise ApiProblem(
                401,
                "invalid_refresh_token",
                "ログイン期限が切れました。もう一度ログインしてください。",
            ) from exc
        raise

    challenge = response.get("ChallengeName")
    if challenge is not None:
        raise RuntimeError(
            f"Cognito refresh flow returned an unexpected challenge: {challenge!r}"
        )

    result = response.get("AuthenticationResult")
    if not isinstance(result, dict):
        raise RuntimeError("Cognito refresh response has no authentication result")

    access_token = result.get("AccessToken")
    token_type = result.get("TokenType")
    expires_in = result.get("ExpiresIn")
    if not isinstance(access_token, str) or not access_token:
        raise RuntimeError("Cognito refresh result has no access token")
    if token_type != "Bearer":
        raise RuntimeError("Cognito refresh result token type is not Bearer")
    if not isinstance(expires_in, int) or isinstance(expires_in, bool) or expires_in <= 0:
        raise RuntimeError("Cognito refresh result has an invalid expiry")

    return {
        "state": "authenticated",
        "access_token": access_token,
        "token_type": token_type,
        "expires_in": expires_in,
    }
