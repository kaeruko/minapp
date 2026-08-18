from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from typing import Any, Mapping

from directory_core import (
    DirectoryProblem,
    descriptor_from_tenant,
    hash_classroom_code,
    normalize_classroom_code,
    strict_json_object,
    validate_tenant_id,
)
from directory_store import DirectoryStore

_LOGGER = logging.getLogger(__name__)
_TENANT_PATH_RE = re.compile(r"^/v1/tenants/([0-9a-f]{32})$")


def _positive_int(name: str, default: int) -> int:
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"{name} must be a positive integer") from exc
    if value < 1:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


def _response(status_code: int, payload: Mapping[str, object]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
        },
        "body": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
    }


def _problem(problem: DirectoryProblem) -> dict[str, Any]:
    return _response(
        problem.status_code,
        {"error": problem.code, "message": problem.message},
    )


def _source_ip(event: Mapping[str, Any]) -> str:
    request_context = event.get("requestContext")
    if not isinstance(request_context, Mapping):
        raise DirectoryProblem(400, "invalid_request", "The request context is invalid.")
    http = request_context.get("http")
    if not isinstance(http, Mapping):
        raise DirectoryProblem(400, "invalid_request", "The request context is invalid.")
    source_ip = http.get("sourceIp")
    if not isinstance(source_ip, str) or not source_ip:
        raise DirectoryProblem(400, "invalid_request", "The request source is invalid.")
    return source_ip


def _method(event: Mapping[str, Any]) -> str:
    request_context = event.get("requestContext")
    if not isinstance(request_context, Mapping):
        return ""
    http = request_context.get("http")
    if not isinstance(http, Mapping):
        return ""
    method = http.get("method")
    return method if isinstance(method, str) else ""


def _headers(event: Mapping[str, Any]) -> dict[str, str]:
    raw = event.get("headers")
    if raw is None:
        return {}
    if not isinstance(raw, Mapping):
        raise DirectoryProblem(400, "invalid_request", "The request headers are invalid.")
    result: dict[str, str] = {}
    for key, value in raw.items():
        if isinstance(key, str) and isinstance(value, str):
            result[key.lower()] = value
    return result


def _load_store() -> DirectoryStore:
    return DirectoryStore.from_environment(os.environ)


def _rate_limit(event: Mapping[str, Any], store: Any) -> None:
    source_hash = hashlib.sha256(_source_ip(event).encode("utf-8")).hexdigest()
    window_seconds = _positive_int("RATE_LIMIT_WINDOW_SECONDS", 60)
    request_limit = _positive_int("RATE_LIMIT_REQUESTS", 60)
    now_epoch = store.now_epoch() if hasattr(store, "now_epoch") else 0
    allowed = store.consume_rate_limit(
        source_hash,
        now_epoch=now_epoch,
        window_seconds=window_seconds,
        request_limit=request_limit,
    )
    if not allowed:
        raise DirectoryProblem(
            429,
            "rate_limited",
            "Too many Directory requests. Try again later.",
        )


def _tenant_for_public_read(tenant: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if tenant is None:
        raise DirectoryProblem(404, "classroom_not_found", "The classroom was not found.")
    status = tenant.get("status")
    if status == "inactive":
        raise DirectoryProblem(410, "classroom_inactive", "The classroom is inactive.")
    if status != "active":
        raise DirectoryProblem(404, "classroom_not_found", "The classroom was not found.")
    return tenant


def _resolve(event: Mapping[str, Any], store: Any) -> dict[str, Any]:
    if event.get("isBase64Encoded") is True:
        raise DirectoryProblem(400, "invalid_request", "Base64 request bodies are not accepted.")
    if event.get("rawQueryString") not in (None, ""):
        raise DirectoryProblem(400, "invalid_request", "Query parameters are not accepted.")
    content_type = _headers(event).get("content-type", "")
    if content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise DirectoryProblem(400, "invalid_request", "Content-Type must be application/json.")

    payload = strict_json_object(event.get("body"), expected_fields={"code"})
    try:
        normalized = normalize_classroom_code(payload.get("code"))
    except ValueError as exc:
        raise DirectoryProblem(
            400,
            "invalid_classroom_code",
            "The classroom code format is invalid.",
        ) from exc
    code_hash = hash_classroom_code(normalized)
    mapping = store.get_code_mapping(code_hash)
    if mapping is None or mapping.get("status") != "active":
        raise DirectoryProblem(404, "classroom_not_found", "The classroom was not found.")
    tenant_id = mapping.get("tenant_id")
    try:
        tenant_id = validate_tenant_id(tenant_id)
    except ValueError as exc:
        raise DirectoryProblem(
            409,
            "incompatible_tenant_config",
            "The classroom routing record is invalid.",
        ) from exc
    tenant = _tenant_for_public_read(store.get_tenant(tenant_id))
    descriptor = descriptor_from_tenant(
        tenant,
        valid_for_seconds=_positive_int("DESCRIPTOR_TTL_SECONDS", 86400),
    )
    _LOGGER.info("classroom resolved code_hash=%s tenant_id=%s", code_hash[:12], tenant_id)
    return _response(200, descriptor)


def _tenant_refresh(path: str, event: Mapping[str, Any], store: Any) -> dict[str, Any]:
    if event.get("rawQueryString") not in (None, ""):
        raise DirectoryProblem(400, "invalid_request", "Query parameters are not accepted.")
    if event.get("body") not in (None, ""):
        raise DirectoryProblem(400, "invalid_request", "GET requests must not include a body.")
    match = _TENANT_PATH_RE.fullmatch(path)
    if match is None:
        raise DirectoryProblem(400, "invalid_tenant_id", "The tenant ID format is invalid.")
    tenant_id = match.group(1)
    tenant = _tenant_for_public_read(store.get_tenant(tenant_id))
    descriptor = descriptor_from_tenant(
        tenant,
        valid_for_seconds=_positive_int("DESCRIPTOR_TTL_SECONDS", 86400),
    )
    _LOGGER.info("tenant descriptor refreshed tenant_id=%s", tenant_id)
    return _response(200, descriptor)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    if not isinstance(event, dict):
        return _problem(DirectoryProblem(400, "invalid_request", "The request is invalid."))

    try:
        store = _load_store()
        _rate_limit(event, store)
        method = _method(event)
        path = event.get("rawPath")
        if not isinstance(path, str):
            raise DirectoryProblem(400, "invalid_request", "The request path is invalid.")

        if method == "POST" and path == "/v1/classrooms/resolve":
            return _resolve(event, store)
        if method == "GET" and path.startswith("/v1/tenants/"):
            return _tenant_refresh(path, event, store)
        raise DirectoryProblem(404, "not_found", "The requested endpoint does not exist.")
    except DirectoryProblem as problem:
        return _problem(problem)
    except Exception as exc:
        _LOGGER.error("Directory request failed error_type=%s", type(exc).__name__)
        return _problem(
            DirectoryProblem(
                503,
                "directory_unavailable",
                "The Directory is temporarily unavailable.",
            )
        )
