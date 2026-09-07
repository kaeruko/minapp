from __future__ import annotations

import re
from typing import Any, Protocol

from handler import _json_body, _json_response, _raw_path, _request_method, _require_fields
from hosted_handler import _empty_response

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


def _get_backend() -> UserStateBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_preview_state_backend import HostedPreviewStateBackend

        _BACKEND = HostedPreviewStateBackend.from_environment()
    return _BACKEND


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    match = _RUNTIME_USER_STATE_RE.fullmatch(_raw_path(event))
    if match is None:
        return None

    token, key = match.groups()
    method = _request_method(event)
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
