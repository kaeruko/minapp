from __future__ import annotations

import logging
import re
from typing import Any

from display_name_backend import DisplayNameAwsBackend
from errors import ApiProblem
from handler import (
    _auth_subject,
    _json_body,
    _json_response,
    _raw_path,
    _request_method,
    _require_fields,
    _required_string,
)

_LOGGER = logging.getLogger(__name__)
_BACKEND: DisplayNameAwsBackend | None = None
_ID_RE = r"([0-9a-f]{32})"
_GROUP_DISPLAY_NAMES_RE = re.compile(rf"^/groups/{_ID_RE}/display-names$")
_USER_DISPLAY_NAME_RE = re.compile(rf"^/users/{_ID_RE}/display-name$")


def _get_backend() -> DisplayNameAwsBackend:
    global _BACKEND
    if _BACKEND is None:
        _BACKEND = DisplayNameAwsBackend.from_environment()
    return _BACKEND


def _display_name(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "display_name", min_length=1, max_length=40)
    if value != value.strip():
        raise ApiProblem(400, "invalid_request", "display_name must not have leading or trailing whitespace.")
    return value


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    if path == "/me/display-name" and method == "GET":
        return _json_response(200, _get_backend().get_my_display_name(_auth_subject(event)))

    if path == "/me/display-name" and method == "PATCH":
        payload = _json_body(event)
        _require_fields(payload, required={"display_name"})
        return _json_response(
            200,
            _get_backend().set_my_display_name(_auth_subject(event), _display_name(payload)),
        )

    group_match = _GROUP_DISPLAY_NAMES_RE.fullmatch(path)
    if method == "GET" and group_match is not None:
        return _json_response(
            200,
            {
                "members": _get_backend().list_group_display_names(
                    _auth_subject(event),
                    group_match.group(1),
                )
            },
        )

    user_match = _USER_DISPLAY_NAME_RE.fullmatch(path)
    if method == "PATCH" and user_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required={"display_name"})
        return _json_response(
            200,
            _get_backend().set_user_display_name(
                _auth_subject(event),
                user_match.group(1),
                _display_name(payload),
            ),
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
            "display_name_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
