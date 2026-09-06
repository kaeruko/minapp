from __future__ import annotations

import re
from typing import Any, Protocol

from handler import _json_body, _json_response, _raw_path, _request_method, _require_fields
from hosted_handler import _empty_response

_ID_RE = r"([0-9a-f]{32})"
_GROUP_APP_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}$")
_RUNTIME_USER_STATE_RE = re.compile(
    r"^/hosted/runtime/([A-Za-z0-9_-]{32,64})/user-state/([^/]{1,128})$"
)
_BACKEND: "UserStateBackend | None" = None


class UserStateBackend(Protocol):
    def get_runtime_user_state(self, token: str, key: str) -> dict[str, Any]: ...

    def set_runtime_user_state(
        self, token: str, key: str, value: Any
    ) -> dict[str, Any]: ...

    def delete_runtime_user_state(self, token: str, key: str) -> None: ...

    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None: ...


def _get_backend() -> UserStateBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_user_state_backend import HostedUserStateBackend

        _BACKEND = HostedUserStateBackend.from_environment()
    return _BACKEND


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    path = _raw_path(event)
    method = _request_method(event)

    app_match = _GROUP_APP_RE.fullmatch(path)
    if method == "DELETE" and app_match is not None:
        from handler import _auth_subject

        group_id, app_id = app_match.groups()
        _get_backend().delete_hosted_app(_auth_subject(event), group_id, app_id)
        return _empty_response()

    match = _RUNTIME_USER_STATE_RE.fullmatch(path)
    if match is None:
        return None

    token, key = match.groups()
    backend = _get_backend()
    if method == "GET":
        return _json_response(200, backend.get_runtime_user_state(token, key))
    if method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required={"value"})
        return _json_response(
            200,
            backend.set_runtime_user_state(token, key, payload["value"]),
        )
    if method == "DELETE":
        backend.delete_runtime_user_state(token, key)
        return _empty_response()
    return None
