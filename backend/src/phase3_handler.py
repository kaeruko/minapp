from __future__ import annotations

import base64
import json
import logging
import re
from typing import Any
from urllib.parse import unquote

from errors import ApiProblem
from phase3_backend import Phase3AwsBackend

_LOGGER = logging.getLogger(__name__)
_BACKEND: Phase3AwsBackend | None = None
_ID_RE = r"([0-9a-f]{32})"
_MOBILE_LAUNCH_RE = re.compile(rf"^/mobile/apps/{_ID_RE}/versions/{_ID_RE}/launch$")
_LAUNCH_CONTENT_RE = re.compile(r"^/launch/([A-Za-z0-9_-]{32,64})/(.+)$")
MAX_JSON_BODY_BYTES = 16 * 1024


def _get_backend() -> Phase3AwsBackend:
    global _BACKEND
    if _BACKEND is None:
        _BACKEND = Phase3AwsBackend.from_environment()
    return _BACKEND


def _json_response(status_code: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
        },
        "body": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
    }


def _content_response(data: bytes, content_type: str) -> dict[str, Any]:
    if not isinstance(data, bytes):
        raise TypeError("content response data must be bytes")
    if not isinstance(content_type, str) or not content_type:
        raise TypeError("content_type must be a non-empty string")
    return {
        "statusCode": 200,
        "headers": {
            "content-type": content_type,
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
            "referrer-policy": "no-referrer",
            "permissions-policy": "camera=(), microphone=(), geolocation=()",
            "content-security-policy": (
                "default-src 'self'; "
                "script-src 'self' 'unsafe-inline'; "
                "style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data: blob:; "
                "media-src 'self'; font-src 'self' data:; "
                "connect-src 'none'; object-src 'none'; base-uri 'none'; "
                "form-action 'none'; frame-src 'none'"
            ),
        },
        "body": base64.b64encode(data).decode("ascii"),
        "isBase64Encoded": True,
    }


def _request_method(event: dict[str, Any]) -> str:
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    http = request_context.get("http")
    if not isinstance(http, dict):
        raise ValueError("requestContext.http must be an object")
    method = http.get("method")
    if not isinstance(method, str) or not method:
        raise ValueError("requestContext.http.method must be a non-empty string")
    return method.upper()


def _raw_path(event: dict[str, Any]) -> str:
    raw_path = event.get("rawPath")
    if not isinstance(raw_path, str) or not raw_path.startswith("/"):
        raise ValueError("rawPath must be an absolute path string")
    return raw_path


def _auth_subject(event: dict[str, Any]) -> str:
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    authorizer = request_context.get("authorizer")
    if not isinstance(authorizer, dict):
        raise ApiProblem(401, "unauthorized", "Authentication is required.")
    jwt = authorizer.get("jwt")
    if not isinstance(jwt, dict):
        raise ApiProblem(401, "unauthorized", "Authentication is required.")
    claims = jwt.get("claims")
    if not isinstance(claims, dict):
        raise ApiProblem(401, "unauthorized", "Authentication is required.")
    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject:
        raise ApiProblem(401, "unauthorized", "The authentication token has no subject.")
    return subject


def _empty_json_body(event: dict[str, Any]) -> None:
    headers = event.get("headers")
    if not isinstance(headers, dict):
        raise ApiProblem(415, "unsupported_media_type", "Content-Type must be application/json.")
    content_type = None
    for name, value in headers.items():
        if isinstance(name, str) and name.lower() == "content-type":
            content_type = value
            break
    if not isinstance(content_type, str) or content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise ApiProblem(415, "unsupported_media_type", "Content-Type must be application/json.")
    if event.get("isBase64Encoded") is True:
        raise ApiProblem(400, "invalid_request", "Base64-encoded JSON bodies are not supported.")
    body = event.get("body")
    if not isinstance(body, str) or not body:
        raise ApiProblem(400, "invalid_request", "A non-empty JSON request body is required.")
    if len(body.encode("utf-8")) > MAX_JSON_BODY_BYTES:
        raise ApiProblem(413, "request_too_large", "The JSON request body is too large.")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ApiProblem(400, "invalid_json", "The request body is not valid JSON.") from exc
    if payload != {}:
        raise ApiProblem(400, "invalid_request", "The JSON request body must be an empty object.")


def _absolute_url(event: dict[str, Any], content_path: str) -> str:
    if not content_path.startswith("/"):
        raise RuntimeError("content_path must be absolute")
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    domain_name = request_context.get("domainName")
    if not isinstance(domain_name, str) or not domain_name:
        raise RuntimeError("API Gateway requestContext.domainName is required for launch URLs")
    return f"https://{domain_name}{content_path}"


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    content_match = _LAUNCH_CONTENT_RE.fullmatch(path)
    if method == "GET" and content_match is not None:
        token, encoded_path = content_match.groups()
        data, content_type = _get_backend().get_launch_file(token, unquote(encoded_path))
        return _content_response(data, content_type)

    if method == "GET" and path == "/mobile/apps":
        return _json_response(
            200,
            {"apps": _get_backend().list_mobile_apps(_auth_subject(event))},
        )

    launch_match = _MOBILE_LAUNCH_RE.fullmatch(path)
    if method == "POST" and launch_match is not None:
        _empty_json_body(event)
        app_id, version_id = launch_match.groups()
        launch = _get_backend().create_launch(
            _auth_subject(event),
            app_id,
            version_id,
        )
        content_path = launch.get("content_path")
        expires_in = launch.get("expires_in")
        if not isinstance(content_path, str):
            raise RuntimeError("Launch backend response has no content_path")
        if not isinstance(expires_in, int) or expires_in <= 0:
            raise RuntimeError("Launch backend response has invalid expires_in")
        return _json_response(
            200,
            {
                "url": _absolute_url(event, content_path),
                "expires_in": expires_in,
            },
        )

    return _json_response(
        404,
        {"error": "not_found", "message": "The requested endpoint does not exist."},
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        return _handle_request(event)
    except ApiProblem as exc:
        _LOGGER.info(
            "phase3_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
