from __future__ import annotations

import json
from typing import Any

API_VERSION = "0.1.0"


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

    return method


def _raw_path(event: dict[str, Any]) -> str:
    raw_path = event.get("rawPath")
    if not isinstance(raw_path, str) or not raw_path.startswith("/"):
        raise ValueError("rawPath must be an absolute path string")
    return raw_path


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context

    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

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

    return _json_response(
        404,
        {
            "error": "not_found",
            "message": "The requested endpoint does not exist.",
        },
    )
