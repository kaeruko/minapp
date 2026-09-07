from __future__ import annotations

import re
from typing import Any

from errors import ApiProblem
from handler import (
    _auth_subject,
    _json_response,
    _query_parameters,
    _raw_path,
    _request_method,
)
from hosted_authoring_app_contracts import list_authoring_app_contracts

_GROUP_ID_RE = r"([0-9a-f]{32})"
_GROUP_APPS_RE = re.compile(rf"^/hosted/authoring/groups/{_GROUP_ID_RE}/apps$")
_BACKEND: Any | None = None


def _get_backend() -> Any:
    global _BACKEND
    if _BACKEND is None:
        from hosted_authoring_indexed_backend import HostedAuthoringIndexedBackend

        _BACKEND = HostedAuthoringIndexedBackend.from_environment()
    return _BACKEND


def _require_no_body_or_query(event: dict[str, Any]) -> None:
    body = event.get("body")
    if body not in (None, "") or event.get("isBase64Encoded") is True:
        raise ApiProblem(400, "invalid_request", "This Authoring request must not contain a body.")
    params = _query_parameters(event)
    if params:
        raise ApiProblem(
            400,
            "invalid_request",
            f"Unknown query parameter(s): {', '.join(sorted(params))}.",
        )


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    match = _GROUP_APPS_RE.fullmatch(_raw_path(event))
    if match is None or _request_method(event) != "GET":
        return None

    _require_no_body_or_query(event)
    return _json_response(
        200,
        {
            "apps": list_authoring_app_contracts(
                _get_backend(),
                _auth_subject(event),
                match.group(1),
            )
        },
    )
