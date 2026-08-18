from __future__ import annotations

import json
import logging
import re
from typing import Any

from errors import ApiProblem
from handler import (
    _auth_subject,
    _header,
    _json_body,
    _json_response,
    _raw_path,
    _request_method,
    _require_fields,
    _zip_body,
)
from phase4_moderation_backend import Phase4ModerationAwsBackend

_LOGGER = logging.getLogger(__name__)
_BACKEND: Phase4ModerationAwsBackend | None = None
_ID_RE = r"([0-9a-f]{32})"
_VERSION_UPLOAD_RE = re.compile(rf"^/apps/{_ID_RE}/versions$")
_APP_RE = re.compile(rf"^/apps/{_ID_RE}$")
_APPROVE_RE = re.compile(rf"^/apps/{_ID_RE}/versions/{_ID_RE}/approve$")
_MODERATION_RE = re.compile(rf"^/apps/{_ID_RE}/versions/{_ID_RE}/(reject|unpublish)$")


def _get_backend() -> Phase4ModerationAwsBackend:
    global _BACKEND
    if _BACKEND is None:
        _BACKEND = Phase4ModerationAwsBackend.from_environment()
    return _BACKEND


def _filename(event: dict[str, Any]) -> str:
    raw = event.get("queryStringParameters")
    if not isinstance(raw, dict) or set(raw) != {"filename"}:
        raise ApiProblem(400, "invalid_request", "filename query parameter is required and must be the only query parameter.")
    value = raw.get("filename")
    if not isinstance(value, str):
        raise ApiProblem(400, "invalid_request", "filename must be a string.")
    if (
        len(value) < 5
        or len(value) > 120
        or value != value.strip()
        or "/" in value
        or "\\" in value
        or not value.lower().endswith(".zip")
        or any(ord(char) < 0x20 or ord(char) == 0x7F for char in value)
    ):
        raise ApiProblem(400, "invalid_request", "filename must be a simple .zip filename.")
    return value


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    if method == "GET" and path == "/lifecycle/apps":
        return _json_response(
            200,
            {"apps": _get_backend().list_my_apps_lifecycle(_auth_subject(event))},
        )

    version_match = _VERSION_UPLOAD_RE.fullmatch(path)
    if method == "POST" and version_match is not None:
        return _json_response(
            201,
            _get_backend().upload_app_version(
                _auth_subject(event),
                version_match.group(1),
                _filename(event),
                _zip_body(event),
            ),
        )

    app_match = _APP_RE.fullmatch(path)
    if method == "DELETE" and app_match is not None:
        if _header(event, "content-type") is not None or event.get("body") not in {None, ""}:
            raise ApiProblem(400, "invalid_request", "DELETE /apps/{app_id} must not include a request body.")
        _get_backend().archive_app(_auth_subject(event), app_match.group(1))
        return {
            "statusCode": 204,
            "headers": {"cache-control": "no-store"},
            "body": "",
        }

    moderation_match = _MODERATION_RE.fullmatch(path)
    if method == "POST" and moderation_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required=set())
        app_id, version_id, action = moderation_match.groups()
        if action == "reject":
            result = _get_backend().reject_app(_auth_subject(event), app_id, version_id)
        elif action == "unpublish":
            result = _get_backend().unpublish_app(_auth_subject(event), app_id, version_id)
        else:
            raise RuntimeError(f"Unhandled moderation action: {action}")
        return _json_response(200, result)

    approve_match = _APPROVE_RE.fullmatch(path)
    if method == "POST" and approve_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required=set())
        app_id, version_id = approve_match.groups()
        return _json_response(
            200,
            _get_backend().approve_app(_auth_subject(event), app_id, version_id),
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
            "phase4_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
