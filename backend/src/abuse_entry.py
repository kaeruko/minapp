from __future__ import annotations

import logging
from typing import Any

import handler
import hosted_handler
from abuse_guard import get_abuse_guard, source_ip_from_event
from errors import ApiProblem
from handler import (
    _json_body,
    _json_response,
    _login_id,
    _password,
    _raw_path,
    _request_method,
    _require_fields,
)

_LOGGER = logging.getLogger(__name__)


def _guard_login(event: dict[str, Any]) -> None:
    payload = _json_body(event)
    _require_fields(payload, required={"login_id", "password"})
    login_id = _login_id(payload)
    _password(payload, "password")
    get_abuse_guard().check(
        "login",
        source_ip=source_ip_from_event(event),
        login_id=login_id,
    )


def _guard_register(event: dict[str, Any]) -> None:
    payload = _json_body(event)
    _require_fields(
        payload,
        required={
            "login_id",
            "password",
            "terms_version",
            "privacy_version",
            "terms_accepted",
            "privacy_accepted",
        },
    )
    login_id = _login_id(payload)
    _password(payload, "password")
    hosted_handler._registration_legal_versions(payload)
    get_abuse_guard().check(
        "register",
        source_ip=source_ip_from_event(event),
        login_id=login_id,
    )


def _guard_recover(event: dict[str, Any]) -> None:
    payload = _json_body(event)
    _require_fields(payload, required={"login_id", "recovery_code", "new_password"})
    login_id = _login_id(payload)
    hosted_handler._recovery_code(payload)
    _password(payload, "new_password")
    get_abuse_guard().check(
        "recover",
        source_ip=source_ip_from_event(event),
        login_id=login_id,
    )


def api_lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        if _request_method(event) == "POST" and _raw_path(event) == "/auth/login":
            _guard_login(event)
        return handler.lambda_handler(event, context)
    except ApiProblem as exc:
        _LOGGER.info(
            "abuse_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(exc.status_code, {"error": exc.error, "message": exc.message})


def hosted_lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        method = _request_method(event)
        path = _raw_path(event)
        if method == "POST" and path == "/hosted/register":
            _guard_register(event)
        elif method == "POST" and path == "/hosted/recover":
            _guard_recover(event)
        return hosted_handler.lambda_handler(event, context)
    except ApiProblem as exc:
        _LOGGER.info(
            "hosted_abuse_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(exc.status_code, {"error": exc.error, "message": exc.message})
