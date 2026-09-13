from __future__ import annotations

import logging
import re
from typing import Any

from errors import ApiProblem
from phase3_handler import (
    _absolute_url,
    _auth_subject,
    _empty_json_body,
    _json_object_body,
    _json_response,
    _raw_path,
    _report_reason,
    _request_method,
)
from shop_backend import ShopAwsBackend

_LOGGER = logging.getLogger(__name__)
_BACKEND: ShopAwsBackend | None = None
_ID_RE = r"([0-9a-f]{32})"
_SHOP_ACTION_RE = re.compile(
    rf"^/shop/apps/{_ID_RE}/versions/{_ID_RE}/(launch|download|reports)$"
)
_SHOP_VISIBILITY_RE = re.compile(rf"^/apps/{_ID_RE}/shop-visibility$")


def _get_backend() -> ShopAwsBackend:
    global _BACKEND
    if _BACKEND is None:
        _BACKEND = ShopAwsBackend.from_environment()
    return _BACKEND


def _visibility(event: dict[str, Any]) -> str:
    payload = _json_object_body(event)
    if set(payload) != {"visibility"}:
        raise ApiProblem(
            400,
            "invalid_request",
            "The JSON request body must contain only visibility.",
        )
    value = payload.get("visibility")
    if value not in {"listed", "unlisted"}:
        raise ApiProblem(
            400,
            "invalid_shop_visibility",
            "visibility must be listed or unlisted.",
        )
    return value


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    if method == "GET" and path == "/shop/apps":
        return _json_response(
            200,
            {"apps": _get_backend().list_shop_apps(_auth_subject(event))},
        )

    visibility_match = _SHOP_VISIBILITY_RE.fullmatch(path)
    if method == "PUT" and visibility_match is not None:
        return _json_response(
            200,
            _get_backend().set_shop_visibility(
                _auth_subject(event),
                visibility_match.group(1),
                _visibility(event),
            ),
        )

    action_match = _SHOP_ACTION_RE.fullmatch(path)
    if action_match is not None and method == "POST":
        app_id, version_id, action = action_match.groups()
        if action == "launch":
            _empty_json_body(event)
            launch = _get_backend().create_shop_launch(
                _auth_subject(event), app_id, version_id
            )
            content_path = launch.get("content_path")
            expires_in = launch.get("expires_in")
            if not isinstance(content_path, str):
                raise RuntimeError("Shop launch backend response has no content_path")
            if not isinstance(expires_in, int) or expires_in <= 0:
                raise RuntimeError("Shop launch backend response has invalid expires_in")
            return _json_response(
                200,
                {
                    "url": _absolute_url(event, content_path),
                    "expires_in": expires_in,
                },
            )
        if action == "download":
            _empty_json_body(event)
            return _json_response(
                200,
                _get_backend().create_shop_download(
                    _auth_subject(event), app_id, version_id
                ),
            )
        if action == "reports":
            return _json_response(
                201,
                _get_backend().create_shop_report(
                    _auth_subject(event),
                    app_id,
                    version_id,
                    _report_reason(event),
                ),
            )
        raise RuntimeError(f"Unsupported shop action: {action!r}")

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
            "shop_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
