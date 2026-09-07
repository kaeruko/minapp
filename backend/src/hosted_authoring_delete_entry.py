from __future__ import annotations

import re
from typing import Any, Protocol

from handler import _auth_subject, _raw_path, _request_method
from hosted_authoring_deletion import delete_authoring_project

_CONTENT_ID_RE = r"([0-9a-f]{32})"
_PROJECT_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}$")
_BACKEND: "AuthoringDeleteBackend | None" = None


class AuthoringDeleteBackend(Protocol):
    pass


def _get_backend() -> AuthoringDeleteBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend

        _BACKEND = HostedAuthoringIndexedBackend.from_environment()
    return _BACKEND


def _require_no_body(event: dict[str, Any]) -> None:
    body = event.get("body")
    if body not in (None, "") or event.get("isBase64Encoded") is True:
        from errors import ApiProblem

        raise ApiProblem(
            400,
            "invalid_request",
            "DELETE Authoring project must not contain a request body.",
        )


def _require_no_query(event: dict[str, Any]) -> None:
    raw = event.get("rawQueryString")
    if raw not in (None, ""):
        from errors import ApiProblem

        raise ApiProblem(
            400,
            "invalid_request",
            "DELETE Authoring project must not contain query parameters.",
        )
    params = event.get("queryStringParameters")
    if params not in (None, {}):
        from errors import ApiProblem

        raise ApiProblem(
            400,
            "invalid_request",
            "DELETE Authoring project must not contain query parameters.",
        )


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    if _request_method(event) != "DELETE":
        return None
    match = _PROJECT_RE.fullmatch(_raw_path(event))
    if match is None:
        return None
    _require_no_body(event)
    _require_no_query(event)
    delete_authoring_project(
        _get_backend(),
        _auth_subject(event),
        match.group(1),
    )
    return {
        "statusCode": 204,
        "headers": {"cache-control": "no-store"},
        "body": "",
    }
