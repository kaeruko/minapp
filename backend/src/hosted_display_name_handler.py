from __future__ import annotations

from typing import Any

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
from hosted_display_name_backend import HostedDisplayNameBackend

_BACKEND: HostedDisplayNameBackend | None = None
_PATH = "/hosted/me/display-name"


def _get_backend() -> HostedDisplayNameBackend:
    global _BACKEND
    if _BACKEND is None:
        _BACKEND = HostedDisplayNameBackend.from_environment()
    return _BACKEND


def _display_name(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "display_name", min_length=1, max_length=40)
    if value != value.strip():
        raise ApiProblem(
            400,
            "invalid_request",
            "display_name must not have leading or trailing whitespace.",
        )
    return value


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    method = _request_method(event)
    path = _raw_path(event)
    if path != _PATH:
        return None

    if method == "GET":
        return _json_response(
            200,
            _get_backend().get_my_display_name(_auth_subject(event)),
        )

    if method == "PATCH":
        payload = _json_body(event)
        _require_fields(payload, required={"display_name"})
        return _json_response(
            200,
            _get_backend().set_my_display_name(
                _auth_subject(event),
                _display_name(payload),
            ),
        )

    return _json_response(
        405,
        {"error": "method_not_allowed", "message": "Method not allowed."},
    )
