from __future__ import annotations

import logging
import re
from typing import Any, Protocol

from errors import ApiProblem
from handler import (
    _auth_subject,
    _group_name,
    _json_body,
    _json_response,
    _login_id,
    _password,
    _raw_path,
    _request_method,
    _require_fields,
    _required_string,
)

API_VERSION = "0.1.0"
_LOGGER = logging.getLogger(__name__)
_BACKEND: "Backend | None" = None
_ID_RE = r"([0-9a-f]{32})"
_GROUP_MEMBERS_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/members$")
_GROUP_MEMBER_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/members/{_ID_RE}$")
_GROUP_INVITE_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/invite$")
_GROUP_MEMBERSHIP_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/membership$")


class Backend(Protocol):
    def register(self, login_id: str, password: str) -> dict[str, Any]: ...
    def me(self, auth_subject: str) -> dict[str, Any]: ...
    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]: ...
    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]: ...
    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, str]]: ...
    def create_invite(self, auth_subject: str, group_id: str) -> dict[str, Any]: ...
    def revoke_invite(self, auth_subject: str, group_id: str) -> None: ...
    def join_group(self, auth_subject: str, invite_code: str) -> dict[str, Any]: ...
    def leave_group(self, auth_subject: str, group_id: str) -> None: ...
    def remove_member(self, auth_subject: str, group_id: str, user_id: str) -> None: ...


def _get_backend() -> Backend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_backend import HostedAwsBackend

        _BACKEND = HostedAwsBackend.from_environment()
    return _BACKEND


def _invite_code(payload: dict[str, Any]) -> str:
    return _required_string(payload, "code", min_length=12, max_length=20)


def _empty_response() -> dict[str, Any]:
    return {
        "statusCode": 204,
        "headers": {"cache-control": "no-store"},
        "body": "",
    }


def _handle_request(event: dict[str, Any]) -> dict[str, Any]:
    method = _request_method(event)
    path = _raw_path(event)

    if method == "GET" and path == "/hosted/health":
        return _json_response(
            200,
            {"service": "minapp-hosted-api", "status": "ok", "version": API_VERSION},
        )

    if method == "POST" and path == "/hosted/register":
        payload = _json_body(event)
        _require_fields(payload, required={"login_id", "password"})
        return _json_response(
            201,
            _get_backend().register(_login_id(payload), _password(payload, "password")),
        )

    if method == "GET" and path == "/hosted/me":
        return _json_response(200, _get_backend().me(_auth_subject(event)))

    if method == "GET" and path == "/hosted/groups":
        return _json_response(
            200,
            {"groups": _get_backend().list_groups(_auth_subject(event))},
        )

    if method == "POST" and path == "/hosted/groups":
        payload = _json_body(event)
        _require_fields(payload, required={"name"})
        return _json_response(
            201,
            _get_backend().create_group(_auth_subject(event), _group_name(payload)),
        )

    if method == "POST" and path == "/hosted/groups/join":
        payload = _json_body(event)
        _require_fields(payload, required={"code"})
        return _json_response(
            201,
            _get_backend().join_group(_auth_subject(event), _invite_code(payload)),
        )

    members_match = _GROUP_MEMBERS_RE.fullmatch(path)
    if method == "GET" and members_match is not None:
        return _json_response(
            200,
            {
                "members": _get_backend().list_members(
                    _auth_subject(event), members_match.group(1)
                )
            },
        )

    invite_match = _GROUP_INVITE_RE.fullmatch(path)
    if invite_match is not None and method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required=set())
        return _json_response(
            201,
            _get_backend().create_invite(_auth_subject(event), invite_match.group(1)),
        )
    if invite_match is not None and method == "DELETE":
        _get_backend().revoke_invite(_auth_subject(event), invite_match.group(1))
        return _empty_response()

    membership_match = _GROUP_MEMBERSHIP_RE.fullmatch(path)
    if membership_match is not None and method == "DELETE":
        _get_backend().leave_group(_auth_subject(event), membership_match.group(1))
        return _empty_response()

    member_match = _GROUP_MEMBER_RE.fullmatch(path)
    if member_match is not None and method == "DELETE":
        group_id, user_id = member_match.groups()
        _get_backend().remove_member(_auth_subject(event), group_id, user_id)
        return _empty_response()

    return _json_response(
        404,
        {"error": "not_found", "message": "The requested endpoint does not exist."},
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    if not isinstance(event, dict):
        raise TypeError("event must be a dictionary")
    try:
        return _handle_request(event)
    except ApiProblem as exc:
        _LOGGER.info(
            "hosted_api_problem status=%s error=%s path=%s",
            exc.status_code,
            exc.error,
            event.get("rawPath"),
        )
        return _json_response(
            exc.status_code,
            {"error": exc.error, "message": exc.message},
        )
