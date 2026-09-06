from __future__ import annotations

import re
from typing import Any, Protocol

from handler import _json_body, _json_response, _raw_path, _request_method, _require_fields
from hosted_handler import _empty_response

_RUNTIME_STATE_RE = re.compile(
    r"^/hosted/runtime/([A-Za-z0-9_-]{32,64})/(state|user-state)/([^/]{1,128})$"
)
_BACKEND: "PreviewStateBackend | None" = None


class PreviewStateBackend(Protocol):
    def is_preview_runtime_session(self, token: str) -> bool: ...

    def get_preview_runtime_state(
        self,
        token: str,
        key: str,
        *,
        user_state: bool,
    ) -> dict[str, Any]: ...

    def set_preview_runtime_state(
        self,
        token: str,
        key: str,
        value: Any,
        *,
        user_state: bool,
    ) -> dict[str, Any]: ...

    def delete_preview_runtime_state(
        self,
        token: str,
        key: str,
        *,
        user_state: bool,
    ) -> None: ...


def _get_backend() -> PreviewStateBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_preview_state_backend import HostedPreviewStateBackend

        _BACKEND = HostedPreviewStateBackend.from_environment()
    return _BACKEND


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")

    match = _RUNTIME_STATE_RE.fullmatch(_raw_path(event))
    if match is None:
        return None

    token, namespace, key = match.groups()
    backend = _get_backend()
    if not backend.is_preview_runtime_session(token):
        return None

    user_state = namespace == "user-state"
    method = _request_method(event)
    if method == "GET":
        return _json_response(
            200,
            backend.get_preview_runtime_state(
                token,
                key,
                user_state=user_state,
            ),
        )
    if method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required={"value"})
        return _json_response(
            200,
            backend.set_preview_runtime_state(
                token,
                key,
                payload["value"],
                user_state=user_state,
            ),
        )
    if method == "DELETE":
        backend.delete_preview_runtime_state(
            token,
            key,
            user_state=user_state,
        )
        return _empty_response()
    return None
