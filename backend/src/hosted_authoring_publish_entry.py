from __future__ import annotations

import re
from typing import Any

from handler import _auth_subject, _json_response, _raw_path, _request_method, _require_fields
from hosted_authoring_entry import _authoring_json_body, _expected_revision_field

_CONTENT_ID_RE = r"([0-9a-f]{32})"
_PUBLISH_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}/publish$")
_BACKEND: Any | None = None


def _get_backend() -> Any:
    global _BACKEND
    if _BACKEND is None:
        from hosted_authoring_publish_backend import HostedAuthoringPublishBackend

        _BACKEND = HostedAuthoringPublishBackend.from_environment()
    return _BACKEND


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    if _request_method(event) != "POST":
        return None
    match = _PUBLISH_RE.fullmatch(_raw_path(event))
    if match is None:
        return None
    payload = _authoring_json_body(event)
    _require_fields(payload, required={"expected_revision"})
    return _json_response(
        201,
        _get_backend().publish_authoring_project(
            _auth_subject(event),
            match.group(1),
            expected_revision=_expected_revision_field(payload),
        ),
    )
