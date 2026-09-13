from __future__ import annotations

import logging
import re
from typing import Any
from urllib.parse import unquote

import hosted_handler
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
from hosted_shop_guarded_backend import HostedShopGuardedBackend

_LOGGER = logging.getLogger(__name__)
_BACKEND: HostedShopGuardedBackend | None = None
_ID_RE = r"([0-9a-f]{32})"
_SHOP_ACTION_RE = re.compile(rf"^/shop/apps/{_ID_RE}/(launch|download|reports)$")
_SHOP_VISIBILITY_RE = re.compile(rf"^/apps/{_ID_RE}/shop-visibility$")
_SHOP_CONTENT_RE = re.compile(r"^/shop/content/([A-Za-z0-9_-]{32,128})/(.+)$")


def _shared_backend() -> HostedShopGuardedBackend:
    global _BACKEND
    backend = hosted_handler._BACKEND
    if backend is None:
        resolved = HostedShopGuardedBackend.from_environment()
        hosted_handler._BACKEND = resolved
        _BACKEND = resolved
        return resolved
    if not isinstance(backend, HostedShopGuardedBackend):
        raise RuntimeError("Hosted API backend was initialized with an incompatible backend type")
    if _BACKEND is None:
        _BACKEND = backend
    elif _BACKEND is not backend:
        raise RuntimeError("Hosted and shop handlers must share the same backend instance")
    return backend


def _absolute_url(event: dict[str, Any], content_path: str) -> str:
    if not content_path.startswith("/"):
        raise RuntimeError("content_path must be absolute")
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    domain_name = request_context.get("domainName")
    if not isinstance(domain_name, str) or not domain_name:
        raise RuntimeError("API Gateway requestContext.domainName is required for shop URLs")
    return f"https://{domain_name}{content_path}"


def _version(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "version", min_length=1, max_length=32)
    if re.fullmatch(r"[1-9][0-9]*", value) is None:
        raise ApiProblem(400, "invalid_shop_version", "version must be a positive decimal integer string.")
    return value


def _visibility(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "visibility", min_length=6, max_length=8)
    if value not in {"listed", "unlisted"}:
        raise ApiProblem(400, "invalid_shop_visibility", "visibility must be listed or unlisted.")
    return value


def _reason(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "reason", min_length=1, max_length=80)
    if value != value.strip() or any(ord(char) < 0x20 or ord(char) == 0x7F for char in value):
        raise ApiProblem(400, "invalid_request", "reason must be 1-80 trimmed characters.")
    return value


def _handle_shop_request(event: dict[str, Any]) -> dict[str, Any] | None:
    method = _request_method(event)
    path = _raw_path(event)
    backend = _shared_backend()

    content_match = _SHOP_CONTENT_RE.fullmatch(path)
    if method == "GET" and content_match is not None:
        token, encoded_path = content_match.groups()
        data, content_type = backend.get_shop_file(token, unquote(encoded_path))
        return hosted_handler._published_content_response(data, content_type)

    if method == "GET" and path == "/shop/apps":
        return _json_response(
            200,
            {"apps": backend.list_shop_apps(_auth_subject(event))},
        )

    visibility_match = _SHOP_VISIBILITY_RE.fullmatch(path)
    if method == "PUT" and visibility_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required={"visibility"})
        return _json_response(
            200,
            backend.set_shop_visibility(
                _auth_subject(event),
                visibility_match.group(1),
                _visibility(payload),
            ),
        )

    action_match = _SHOP_ACTION_RE.fullmatch(path)
    if method == "POST" and action_match is not None:
        app_id, action = action_match.groups()
        payload = _json_body(event)
        if action in {"launch", "download"}:
            _require_fields(payload, required={"version"})
            version = _version(payload)
            if action == "launch":
                launch = backend.create_shop_launch(
                    _auth_subject(event), app_id, version
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
            return _json_response(
                200,
                backend.create_shop_download(_auth_subject(event), app_id, version),
            )
        if action == "reports":
            _require_fields(payload, required={"version", "reason"})
            return _json_response(
                201,
                backend.create_shop_report(
                    _auth_subject(event),
                    app_id,
                    _version(payload),
                    _reason(payload),
                ),
            )
        raise RuntimeError(f"Unsupported shop action: {action!r}")

    return None


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        response = _handle_shop_request(event)
        if response is not None:
            return response
        _shared_backend()
        return hosted_handler.lambda_handler(event, context)
    except ApiProblem as exc:
        _LOGGER.info(
            "hosted_shop_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
