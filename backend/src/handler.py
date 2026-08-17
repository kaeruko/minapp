from __future__ import annotations

import json
import logging
import re
from typing import Any, Protocol

from errors import ApiProblem

API_VERSION = "0.2.0"
MAX_JSON_BODY_BYTES = 16 * 1024

_LOGGER = logging.getLogger(__name__)
_BACKEND: "Backend | None" = None


class Backend(Protocol):
    def login(self, login_id: str, password: str) -> dict[str, Any]: ...
    def complete_new_password(
        self, login_id: str, new_password: str, session: str
    ) -> dict[str, Any]: ...
    def me(self, auth_subject: str) -> dict[str, Any]: ...
    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]: ...
    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]: ...
    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]: ...
    def create_student(self, auth_subject: str, group_id: str) -> dict[str, Any]: ...
    def reset_student_password(
        self, auth_subject: str, user_id: str
    ) -> dict[str, Any]: ...
    def remove_member(
        self, auth_subject: str, group_id: str, user_id: str
    ) -> None: ...


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


def _header(event: dict[str, Any], name: str) -> str | None:
    headers = event.get("headers")
    if headers is None:
        return None
    if not isinstance(headers, dict):
        raise ValueError("headers must be an object")

    target = name.lower()
    for raw_name, raw_value in headers.items():
        if not isinstance(raw_name, str) or not isinstance(raw_value, str):
            raise ValueError("headers must contain string keys and values")
        if raw_name.lower() == target:
            return raw_value
    return None


def _json_body(event: dict[str, Any]) -> dict[str, Any]:
    if event.get("isBase64Encoded") is True:
        raise ApiProblem(400, "invalid_request", "Base64-encoded JSON bodies are not supported.")

    content_type = _header(event, "content-type")
    if content_type is None or content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise ApiProblem(415, "unsupported_media_type", "Content-Type must be application/json.")

    body = event.get("body")
    if not isinstance(body, str) or not body:
        raise ApiProblem(400, "invalid_request", "A non-empty JSON request body is required.")

    if len(body.encode("utf-8")) > MAX_JSON_BODY_BYTES:
        raise ApiProblem(413, "request_too_large", "The JSON request body is too large.")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ApiProblem(400, "invalid_json", "The request body is not valid JSON.") from exc

    if not isinstance(payload, dict):
        raise ApiProblem(400, "invalid_request", "The JSON request body must be an object.")
    return payload


def _require_fields(
    payload: dict[str, Any],
    *,
    required: set[str],
    optional: set[str] | None = None,
) -> None:
    optional_fields = optional or set()
    provided = set(payload)

    missing = required - provided
    if missing:
        names = ", ".join(sorted(missing))
        raise ApiProblem(400, "invalid_request", f"Missing required field(s): {names}.")

    unknown = provided - required - optional_fields
    if unknown:
        names = ", ".join(sorted(unknown))
        raise ApiProblem(400, "invalid_request", f"Unknown field(s): {names}.")


def _required_string(
    payload: dict[str, Any],
    field: str,
    *,
    min_length: int,
    max_length: int,
) -> str:
    value = payload.get(field)
    if not isinstance(value, str):
        raise ApiProblem(400, "invalid_request", f"{field} must be a string.")
    if len(value) < min_length or len(value) > max_length:
        raise ApiProblem(
            400,
            "invalid_request",
            f"{field} must be between {min_length} and {max_length} characters.",
        )
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in value):
        raise ApiProblem(400, "invalid_request", f"{field} must not contain control characters.")
    return value


_LOGIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,31}$")


def _login_id(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "login_id", min_length=3, max_length=32)
    if _LOGIN_ID_RE.fullmatch(value) is None:
        raise ApiProblem(
            400,
            "invalid_request",
            "login_id must contain only lowercase ASCII letters, digits, and hyphens.",
        )
    return value


def _password(payload: dict[str, Any], field: str) -> str:
    return _required_string(payload, field, min_length=10, max_length=128)


def _group_name(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "name", min_length=1, max_length=60)
    if value != value.strip():
        raise ApiProblem(400, "invalid_request", "name must not have leading or trailing whitespace.")
    return value


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


_GROUP_MEMBERS_RE = re.compile(r"^/groups/([0-9a-f]{32})/members$")
_GROUP_STUDENTS_RE = re.compile(r"^/groups/([0-9a-f]{32})/students$")
_GROUP_MEMBER_RE = re.compile(r"^/groups/([0-9a-f]{32})/members/([0-9a-f]{32})$")
_RESET_PASSWORD_RE = re.compile(r"^/users/([0-9a-f]{32})/reset-password$")


def _get_backend() -> Backend:
    global _BACKEND
    if _BACKEND is None:
        from aws_backend import AwsBackend

        _BACKEND = AwsBackend.from_environment()
    return _BACKEND


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    if method == "GET" and path == "/health":
        return _json_response(
            200,
            {
                "service": "minapp-api",
                "status": "ok",
                "version": API_VERSION,
            },
        )

    if method == "POST" and path == "/auth/login":
        payload = _json_body(event)
        _require_fields(payload, required={"login_id", "password"})
        result = _get_backend().login(_login_id(payload), _password(payload, "password"))
        return _json_response(200, result)

    if method == "POST" and path == "/auth/change-password":
        payload = _json_body(event)
        _require_fields(payload, required={"login_id", "new_password", "session"})
        session = _required_string(payload, "session", min_length=1, max_length=8192)
        result = _get_backend().complete_new_password(
            _login_id(payload),
            _password(payload, "new_password"),
            session,
        )
        return _json_response(200, result)

    if method == "GET" and path == "/me":
        return _json_response(200, _get_backend().me(_auth_subject(event)))

    if method == "GET" and path == "/groups":
        return _json_response(
            200,
            {"groups": _get_backend().list_groups(_auth_subject(event))},
        )

    if method == "POST" and path == "/groups":
        payload = _json_body(event)
        _require_fields(payload, required={"name"})
        return _json_response(
            201,
            _get_backend().create_group(_auth_subject(event), _group_name(payload)),
        )

    members_match = _GROUP_MEMBERS_RE.fullmatch(path)
    if method == "GET" and members_match is not None:
        group_id = members_match.group(1)
        return _json_response(
            200,
            {"members": _get_backend().list_members(_auth_subject(event), group_id)},
        )

    students_match = _GROUP_STUDENTS_RE.fullmatch(path)
    if method == "POST" and students_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required=set())
        return _json_response(
            201,
            _get_backend().create_student(
                _auth_subject(event),
                students_match.group(1),
            ),
        )

    reset_match = _RESET_PASSWORD_RE.fullmatch(path)
    if method == "POST" and reset_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required=set())
        return _json_response(
            200,
            _get_backend().reset_student_password(
                _auth_subject(event),
                reset_match.group(1),
            ),
        )

    member_match = _GROUP_MEMBER_RE.fullmatch(path)
    if method == "DELETE" and member_match is not None:
        group_id, user_id = member_match.groups()
        _get_backend().remove_member(_auth_subject(event), group_id, user_id)
        return {"statusCode": 204, "headers": {"cache-control": "no-store"}, "body": ""}

    return _json_response(
        404,
        {
            "error": "not_found",
            "message": "The requested endpoint does not exist.",
        },
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context

    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    try:
        return _handle_request(event)
    except ApiProblem as exc:
        _LOGGER.info(
            "api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
