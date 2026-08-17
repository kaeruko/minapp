from __future__ import annotations

import json
import os
from typing import Any

from tenant_identity import TenantIdentity

_IDENTITY = TenantIdentity.from_environment(os.environ)


def _response(status_code: int, payload: dict[str, object]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
        },
        "body": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    http = request_context.get("http")
    if not isinstance(http, dict):
        raise ValueError("requestContext.http must be an object")
    method = http.get("method")
    path = event.get("rawPath")

    if method == "GET" and path == "/tenant-info":
        return _response(200, _IDENTITY.public_payload())

    return _response(
        404,
        {
            "error": "not_found",
            "message": "The requested endpoint does not exist.",
        },
    )
