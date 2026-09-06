from __future__ import annotations

import re
from typing import Any
from urllib.parse import unquote

from errors import ApiProblem
from handler import _auth_subject, _content_response, _json_response, _raw_path, _request_method, _require_fields
from hosted_authoring_entry import (
    _asset_body,
    _authoring_json_body,
    _expected_revision_field,
    _expected_revision_header,
    _require_no_body,
)
import hosted_authoring_launch
import hosted_authoring_session
import hosted_handler

_CONTENT_ID_RE = r"([0-9a-f]{32})"
_TOKEN_RE = r"([A-Za-z0-9_-]{32,64})"
_CREATE_SESSION_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}/session$")
_CREATE_LAUNCH_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}/launch$")
_EDITOR_CONTENT_RE = re.compile(r"^/hosted/authoring-editor/([A-Za-z0-9_-]{32,64})/(.+)$")
_SESSION_PROJECT_RE = re.compile(rf"^/hosted/authoring/session/{_TOKEN_RE}$")
_SESSION_DOCUMENT_RE = re.compile(rf"^/hosted/authoring/session/{_TOKEN_RE}/document$")
_SESSION_PUBLISH_RE = re.compile(rf"^/hosted/authoring/session/{_TOKEN_RE}/publish$")
_SESSION_ASSET_RE = re.compile(rf"^/hosted/authoring/session/{_TOKEN_RE}/assets/(.+)$")
_BACKEND: Any | None = None


def _get_backend() -> Any:
    global _BACKEND
    if _BACKEND is None:
        from hosted_authoring_publish_backend import HostedAuthoringPublishBackend

        _BACKEND = HostedAuthoringPublishBackend.from_environment()
    return _BACKEND


def _editor_app_id(payload: dict[str, Any]) -> str:
    _require_fields(payload, required={"editor_app_id"})
    editor_app_id = payload["editor_app_id"]
    if not isinstance(editor_app_id, str) or re.fullmatch(r"[0-9a-f]{32}", editor_app_id) is None:
        raise ApiProblem(
            400,
            "invalid_request",
            "editor_app_id must be a 32-character lowercase hexadecimal ID.",
        )
    return editor_app_id


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    method = _request_method(event)
    path = _raw_path(event)

    editor_content_match = _EDITOR_CONTENT_RE.fullmatch(path)
    if editor_content_match is not None:
        if method != "GET":
            return None
        token, encoded_path = editor_content_match.groups()
        data, content_type = hosted_authoring_launch.get_editor_file(
            _get_backend(),
            token,
            unquote(encoded_path),
        )
        return hosted_handler._published_content_response(data, content_type)

    create_launch_match = _CREATE_LAUNCH_RE.fullmatch(path)
    if create_launch_match is not None:
        if method != "POST":
            return None
        payload = _authoring_json_body(event)
        return _json_response(
            201,
            hosted_authoring_launch.create_launch(
                _get_backend(),
                _auth_subject(event),
                create_launch_match.group(1),
                _editor_app_id(payload),
            ),
        )

    create_match = _CREATE_SESSION_RE.fullmatch(path)
    if create_match is not None:
        if method != "POST":
            return None
        payload = _authoring_json_body(event)
        return _json_response(
            201,
            hosted_authoring_session.create_session(
                _get_backend(),
                _auth_subject(event),
                create_match.group(1),
                _editor_app_id(payload),
            ),
        )

    project_match = _SESSION_PROJECT_RE.fullmatch(path)
    if project_match is not None:
        if method != "GET":
            return None
        _require_no_body(event)
        return _json_response(
            200,
            hosted_authoring_session.load_project(
                _get_backend(),
                project_match.group(1),
            ),
        )

    document_match = _SESSION_DOCUMENT_RE.fullmatch(path)
    if document_match is not None:
        if method != "POST":
            return None
        payload = _authoring_json_body(event)
        _require_fields(payload, required={"expected_revision", "document"})
        document = payload["document"]
        if not isinstance(document, dict):
            raise ApiProblem(400, "invalid_master_data", "document must be a JSON object.")
        return _json_response(
            200,
            hosted_authoring_session.save_document(
                _get_backend(),
                document_match.group(1),
                expected_revision=_expected_revision_field(payload),
                document=document,
            ),
        )

    publish_match = _SESSION_PUBLISH_RE.fullmatch(path)
    if publish_match is not None:
        if method != "POST":
            return None
        payload = _authoring_json_body(event)
        _require_fields(payload, required={"expected_revision"})
        return _json_response(
            201,
            hosted_authoring_session.publish_project(
                _get_backend(),
                publish_match.group(1),
                expected_revision=_expected_revision_field(payload),
            ),
        )

    asset_match = _SESSION_ASSET_RE.fullmatch(path)
    if asset_match is None:
        return None
    token, encoded_path = asset_match.groups()
    asset_path = unquote(encoded_path)

    if method == "GET":
        _require_no_body(event)
        data, content_type = hosted_authoring_session.get_asset(
            _get_backend(),
            token,
            asset_path,
        )
        return _content_response(data, content_type)
    if method == "POST":
        data = _asset_body(event, asset_path)
        return _json_response(
            200,
            hosted_authoring_session.save_asset(
                _get_backend(),
                token,
                expected_revision=_expected_revision_header(event),
                path=asset_path,
                data=data,
            ),
        )
    if method == "DELETE":
        _require_no_body(event)
        return _json_response(
            200,
            hosted_authoring_session.delete_asset(
                _get_backend(),
                token,
                expected_revision=_expected_revision_header(event),
                path=asset_path,
            ),
        )
    return None
