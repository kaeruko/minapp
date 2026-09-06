from __future__ import annotations

import base64
import binascii
import json
import re
from typing import Any, Protocol
from urllib.parse import unquote

from errors import ApiProblem
from handler import (
    _auth_subject,
    _content_response,
    _header,
    _json_response,
    _raw_path,
    _request_method,
    _require_fields,
)
from hosted_authoring_backend import (
    MAX_AUTHORING_ASSET_BYTES,
    MAX_AUTHORING_DOCUMENT_BYTES,
    _AUTHORING_ASSET_TYPES,
    validate_authoring_asset_path,
)

_CONTENT_ID_RE = r"([0-9a-f]{32})"
_PROJECTS_RE = re.compile(r"^/hosted/authoring/projects$")
_PROJECT_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}$")
_DOCUMENT_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}/document$")
_ASSET_RE = re.compile(rf"^/hosted/authoring/projects/{_CONTENT_ID_RE}/assets/(.+)$")
_MAX_AUTHORING_JSON_BODY_BYTES = MAX_AUTHORING_DOCUMENT_BYTES + 64 * 1024
_BACKEND: "AuthoringBackend | None" = None


class AuthoringBackend(Protocol):
    def create_authoring_project(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str,
        document: dict[str, Any],
    ) -> dict[str, Any]: ...

    def load_authoring_project(
        self,
        auth_subject: str,
        content_id: str,
    ) -> dict[str, Any]: ...

    def save_authoring_document(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        document: dict[str, Any],
    ) -> dict[str, Any]: ...

    def get_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        path: str,
    ) -> tuple[bytes, str]: ...

    def save_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
        data: bytes,
    ) -> dict[str, Any]: ...

    def delete_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
    ) -> dict[str, Any]: ...


def _get_backend() -> AuthoringBackend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_authoring_backend import HostedAuthoringBackend

        _BACKEND = HostedAuthoringBackend.from_environment()
    return _BACKEND


def _authoring_json_body(event: dict[str, Any]) -> dict[str, Any]:
    if event.get("isBase64Encoded") is True:
        raise ApiProblem(
            400,
            "invalid_authoring_json_transport",
            "Authoring JSON bodies must not be base64 encoded.",
        )
    content_type = _header(event, "content-type")
    if content_type is None or content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise ApiProblem(415, "unsupported_media_type", "Content-Type must be application/json.")
    body = event.get("body")
    if not isinstance(body, str) or not body:
        raise ApiProblem(400, "invalid_request", "A non-empty JSON request body is required.")
    if len(body.encode("utf-8")) > _MAX_AUTHORING_JSON_BODY_BYTES:
        raise ApiProblem(413, "authoring_request_too_large", "Authoring JSON request is too large.")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ApiProblem(400, "invalid_json", "The request body is not valid JSON.") from exc
    if not isinstance(payload, dict):
        raise ApiProblem(400, "invalid_request", "The JSON request body must be an object.")
    return payload


def _expected_revision_header(event: dict[str, Any]) -> int:
    raw = _header(event, "x-minapp-expected-revision")
    if raw is None or not raw.isascii() or not raw.isdigit():
        raise ApiProblem(
            400,
            "invalid_expected_revision",
            "x-minapp-expected-revision must be a positive integer.",
        )
    value = int(raw)
    if value < 1:
        raise ApiProblem(
            400,
            "invalid_expected_revision",
            "x-minapp-expected-revision must be a positive integer.",
        )
    return value


def _expected_revision_field(payload: dict[str, Any]) -> int:
    value = payload.get("expected_revision")
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ApiProblem(400, "invalid_expected_revision", "expected_revision must be a positive integer.")
    return value


def _asset_body(event: dict[str, Any], path: str) -> bytes:
    normalized = validate_authoring_asset_path(path)
    suffix = re.search(r"(\.[^.]+)$", normalized)
    if suffix is None:
        raise ApiProblem(400, "unsupported_authoring_asset_type", "Authoring asset has no supported suffix.")
    expected_content_type = _AUTHORING_ASSET_TYPES[suffix.group(1).lower()]
    raw_content_type = _header(event, "content-type")
    content_type = None if raw_content_type is None else raw_content_type.split(";", 1)[0].strip().lower()
    if content_type != expected_content_type:
        raise ApiProblem(
            415,
            "authoring_asset_content_type_mismatch",
            f"Content-Type for {normalized} must be {expected_content_type}.",
        )
    if event.get("isBase64Encoded") is not True:
        raise ApiProblem(
            400,
            "invalid_authoring_asset_transport",
            "Authoring asset request body must be base64 encoded by API Gateway.",
        )
    body = event.get("body")
    if not isinstance(body, str) or not body:
        raise ApiProblem(400, "empty_authoring_asset", "Authoring asset must not be empty.")
    try:
        data = base64.b64decode(body, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ApiProblem(
            400,
            "invalid_authoring_asset_transport",
            "Authoring asset request body has invalid base64 data.",
        ) from exc
    if len(data) > MAX_AUTHORING_ASSET_BYTES:
        raise ApiProblem(
            413,
            "authoring_asset_too_large",
            f"Authoring asset must be at most {MAX_AUTHORING_ASSET_BYTES} bytes.",
        )
    return data


def _require_no_body(event: dict[str, Any]) -> None:
    body = event.get("body")
    if body not in (None, "") or event.get("isBase64Encoded") is True:
        raise ApiProblem(400, "invalid_request", "This Authoring request must not contain a body.")


def handle_request(event: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    method = _request_method(event)
    path = _raw_path(event)

    if _PROJECTS_RE.fullmatch(path) is not None:
        if method != "POST":
            return None
        payload = _authoring_json_body(event)
        _require_fields(payload, required={"group_id", "content_format", "document"})
        group_id = payload["group_id"]
        content_format = payload["content_format"]
        document = payload["document"]
        if not isinstance(group_id, str) or re.fullmatch(r"[0-9a-f]{32}", group_id) is None:
            raise ApiProblem(400, "invalid_request", "group_id must be a 32-character lowercase hexadecimal ID.")
        if not isinstance(content_format, str):
            raise ApiProblem(400, "invalid_content_format", "content_format must be a string.")
        if not isinstance(document, dict):
            raise ApiProblem(400, "invalid_master_data", "document must be a JSON object.")
        return _json_response(
            201,
            _get_backend().create_authoring_project(
                _auth_subject(event),
                group_id,
                content_format,
                document,
            ),
        )

    project_match = _PROJECT_RE.fullmatch(path)
    if project_match is not None:
        if method != "GET":
            return None
        _require_no_body(event)
        return _json_response(
            200,
            _get_backend().load_authoring_project(
                _auth_subject(event),
                project_match.group(1),
            ),
        )

    document_match = _DOCUMENT_RE.fullmatch(path)
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
            _get_backend().save_authoring_document(
                _auth_subject(event),
                document_match.group(1),
                expected_revision=_expected_revision_field(payload),
                document=document,
            ),
        )

    asset_match = _ASSET_RE.fullmatch(path)
    if asset_match is None:
        return None
    content_id, encoded_path = asset_match.groups()
    asset_path = unquote(encoded_path)

    if method == "GET":
        _require_no_body(event)
        data, content_type = _get_backend().get_authoring_asset(
            _auth_subject(event),
            content_id,
            asset_path,
        )
        return _content_response(data, content_type)
    if method == "POST":
        expected_revision = _expected_revision_header(event)
        data = _asset_body(event, asset_path)
        return _json_response(
            200,
            _get_backend().save_authoring_asset(
                _auth_subject(event),
                content_id,
                expected_revision=expected_revision,
                path=asset_path,
                data=data,
            ),
        )
    if method == "DELETE":
        _require_no_body(event)
        return _json_response(
            200,
            _get_backend().delete_authoring_asset(
                _auth_subject(event),
                content_id,
                expected_revision=_expected_revision_header(event),
                path=asset_path,
            ),
        )
    return None
