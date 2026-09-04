from __future__ import annotations

import logging
import re
from typing import Any, Protocol

from errors import ApiProblem
from handler import (
    _auth_subject,
    _json_body,
    _json_response,
    _query_parameters,
    _raw_path,
    _request_method,
    _require_fields,
    _zip_body,
)
import hosted_app_management
import hosted_handler
from hosted_upload import create_uploaded_app

_LOGGER = logging.getLogger(__name__)
_BACKEND: "LaunchBackend | None" = None
_ID_RE = r"([0-9a-f]{32})"
_LAUNCH_SESSION_RE = re.compile(
    rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/launch-session$"
)
_GROUP_APP_UPLOAD_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/upload$")
_MY_APP_RE = re.compile(rf"^/hosted/my/apps/{_ID_RE}$")
_MY_APP_VISIBILITY_RE = re.compile(rf"^/hosted/my/apps/{_ID_RE}/visibility$")


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


def _upload_title(event: dict[str, Any]) -> str:
    parameters = _query_parameters(event)
    if set(parameters) != {"title"}:
        raise ApiProblem(
            400,
            "invalid_request",
            "ZIP upload requires exactly one title query parameter.",
        )
    title = parameters["title"]
    if not isinstance(title, str) or not title or len(title) > 80 or title != title.strip():
        raise ApiProblem(
            400,
            "invalid_request",
            "title must be a trimmed non-empty string up to 80 characters.",
        )
    return title


def _handle_upload_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if _request_method(event) != "POST":
        return None
    match = _GROUP_APP_UPLOAD_RE.fullmatch(_raw_path(event))
    if match is None:
        return None
    return _json_response(
        201,
        create_uploaded_app(
            _get_backend(),
            _auth_subject(event),
            match.group(1),
            _upload_title(event),
            _zip_body(event),
        ),
    )


def _handle_management_request(event: dict[str, Any]) -> dict[str, Any] | None:
    method = _request_method(event)
    path = _raw_path(event)

    if method == "GET" and path == "/hosted/my/apps":
        auth_subject = _auth_subject(event)
        backend = _get_backend()
        return _json_response(
            200,
            {"apps": hosted_app_management.list_managed_apps(backend, auth_subject)},
        )

    app_match = _MY_APP_RE.fullmatch(path)
    if method == "GET" and app_match is not None:
        auth_subject = _auth_subject(event)
        backend = _get_backend()
        return _json_response(
            200,
            hosted_app_management.get_managed_app(
                backend,
                auth_subject,
                app_match.group(1),
            ),
        )

    visibility_match = _MY_APP_VISIBILITY_RE.fullmatch(path)
    if method == "POST" and visibility_match is not None:
        payload = _json_body(event)
        _require_fields(payload, required={"hidden"})
        hidden = payload["hidden"]
        if not isinstance(hidden, bool):
            raise ApiProblem(400, "invalid_request", "hidden must be a boolean.")
        auth_subject = _auth_subject(event)
        backend = _get_backend()
        return _json_response(
            200,
            hosted_app_management.set_visibility(
                backend,
                auth_subject,
                visibility_match.group(1),
                hidden=hidden,
            ),
        )
    return None


def _handle_launch_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if _request_method(event) != "POST":
        return None
    match = _LAUNCH_SESSION_RE.fullmatch(_raw_path(event))
    if match is None:
        return None
    payload = _json_body(event)
    _require_fields(payload, required=set())
    group_id, app_id = match.groups()
    auth_subject = _auth_subject(event)
    backend = _get_backend()
    hosted_app_management.require_visible(backend, group_id, app_id)
    result = backend.create_launch_session(auth_subject, group_id, app_id)
    user = backend._user_by_auth_subject(auth_subject)  # type: ignore[attr-defined]
    hosted_app_management.record_launch(
        backend,
        group_id=group_id,
        app_id=app_id,
        user_id=user.user_id,
    )
    return _json_response(201, result)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        upload_response = _handle_upload_request(event)
        if upload_response is not None:
            return upload_response
        management_response = _handle_management_request(event)
        if management_response is not None:
            return management_response
        launch_response = _handle_launch_request(event)
        if launch_response is not None:
            return launch_response
    except ApiProblem as exc:
        _LOGGER.info(
            "hosted_entry_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )

    # Existing Hosted and dedicated/school behavior stays in its current handler.
    # This entrypoint only intercepts Hosted routes that need separate handling.
    return hosted_handler.lambda_handler(event, context)
