from __future__ import annotations

import logging
import re
from typing import Any, Protocol

from errors import ApiProblem
from handler import (
    _auth_subject,
    _json_body,
    _json_response,
    _raw_path,
    _request_method,
    _require_fields,
)
import hosted_handler

_LOGGER = logging.getLogger(__name__)
_BACKEND: "LaunchBackend | None" = None
_ID_RE = r"([0-9a-f]{32})"
_LAUNCH_SESSION_RE = re.compile(
    rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/launch-session$"
)


class LaunchBackend(Protocol):
    def create_launch_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]: ...


def _get_backend() -> LaunchBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_legal_backend import HostedLegalBackend

        _BACKEND = HostedLegalBackend.from_environment()
    return _BACKEND


def _handle_launch_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if _request_method(event) != "POST":
        return None
    match = _LAUNCH_SESSION_RE.fullmatch(_raw_path(event))
    if match is None:
        return None
    payload = _json_body(event)
    _require_fields(payload, required=set())
    group_id, app_id = match.groups()
    return _json_response(
        201,
        _get_backend().create_launch_session(
            _auth_subject(event),
            group_id,
            app_id,
        ),
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        launch_response = _handle_launch_request(event)
        if launch_response is not None:
            return launch_response
    except ApiProblem as exc:
        _LOGGER.info(
            "hosted_launch_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )

    # Existing Hosted and dedicated/school behavior stays in its current handler.
    # This entrypoint only intercepts the new Hosted launch-session route.
    return hosted_handler.lambda_handler(event, context)
