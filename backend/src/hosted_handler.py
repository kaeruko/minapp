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
from hosted_legal import legal_payload, validate_legal_versions

API_VERSION = "0.3.0"
_LOGGER = logging.getLogger(__name__)
_BACKEND: "Backend | None" = None
_ID_RE = r"([0-9a-f]{32})"
_GROUP_MEMBERS_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/members$")
_GROUP_MEMBER_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/members/{_ID_RE}$")
_GROUP_INVITE_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/invite$")
_GROUP_MEMBERSHIP_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/membership$")
_GROUP_OWNER_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/owner$")
_GROUP_RE = re.compile(rf"^/hosted/groups/{_ID_RE}$")
_GROUP_APPS_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps$")
_GROUP_APP_INSTALL_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/install$")
_GROUP_APP_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}$")
_GROUP_APP_FORK_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/fork$")
_RUNTIME_SESSION_RE = re.compile(rf"^/hosted/groups/{_ID_RE}/apps/{_ID_RE}/runtime-session$")
_RUNTIME_STATE_RE = re.compile(r"^/hosted/runtime/([A-Za-z0-9_-]{32,64})/state/([^/]{1,128})$")
_BUILTIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")


class Backend(Protocol):
    def register(
        self,
        login_id: str,
        password: str,
        terms_version: str,
        privacy_version: str,
    ) -> dict[str, Any]: ...
    def recover_account(
        self, login_id: str, recovery_code: str, new_password: str
    ) -> dict[str, Any]: ...
    def rotate_recovery_code(self, auth_subject: str) -> dict[str, str]: ...
    def delete_account(self, auth_subject: str) -> None: ...
    def me(self, auth_subject: str) -> dict[str, Any]: ...
    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]: ...
    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]: ...
    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, str]]: ...
    def create_invite(self, auth_subject: str, group_id: str) -> dict[str, Any]: ...
    def revoke_invite(self, auth_subject: str, group_id: str) -> None: ...
    def join_group(self, auth_subject: str, invite_code: str) -> dict[str, Any]: ...
    def leave_group(self, auth_subject: str, group_id: str) -> None: ...
    def remove_member(self, auth_subject: str, group_id: str, user_id: str) -> None: ...
    def transfer_group_ownership(
        self, auth_subject: str, group_id: str, new_owner_user_id: str
    ) -> dict[str, str]: ...
    def delete_group(self, auth_subject: str, group_id: str) -> None: ...
    def list_builtin_templates(self) -> list[dict[str, Any]]: ...
    def list_group_apps(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]: ...
    def install_builtin(
        self, auth_subject: str, group_id: str, builtin_id: str
    ) -> dict[str, Any]: ...
    def fork_app(
        self, auth_subject: str, group_id: str, app_id: str, title: str
    ) -> dict[str, Any]: ...
    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None: ...
    def create_runtime_session(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> dict[str, Any]: ...
    def get_runtime_state(self, token: str, key: str) -> dict[str, Any]: ...
    def set_runtime_state(self, token: str, key: str, value: Any) -> dict[str, Any]: ...
    def delete_runtime_state(self, token: str, key: str) -> None: ...


def _get_backend() -> Backend:
    global _BACKEND
    if _BACKEND is None:
        from hosted_legal_backend import HostedLegalBackend

        _BACKEND = HostedLegalBackend.from_environment()
    return _BACKEND


def _invite_code(payload: dict[str, Any]) -> str:
    return _required_string(payload, "code", min_length=12, max_length=20)


def _recovery_code(payload: dict[str, Any]) -> str:
    return _required_string(payload, "recovery_code", min_length=20, max_length=30)


def _required_boolean(payload: dict[str, Any], field: str) -> bool:
    value = payload.get(field)
    if not isinstance(value, bool):
        raise ApiProblem(400, "invalid_request", f"{field} must be a boolean.")
    return value


def _registration_legal_versions(payload: dict[str, Any]) -> tuple[str, str]:
    terms_version = _required_string(payload, "terms_version", min_length=1, max_length=80)
    privacy_version = _required_string(payload, "privacy_version", min_length=1, max_length=80)
    if not _required_boolean(payload, "terms_accepted"):
        raise ApiProblem(400, "terms_not_accepted", "利用規約への同意が必要です。")
    if not _required_boolean(payload, "privacy_accepted"):
        raise ApiProblem(400, "privacy_not_accepted", "プライバシーポリシーへの同意が必要です。")
    validate_legal_versions(terms_version, privacy_version)
    return terms_version, privacy_version


def _user_id(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "user_id", min_length=32, max_length=32)
    if re.fullmatch(r"[0-9a-f]{32}", value) is None:
        raise ApiProblem(400, "invalid_request", "user_id must be a 32-character lowercase hexadecimal ID.")
    return value


def _builtin_id(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "builtin_id", min_length=2, max_length=64)
    if _BUILTIN_ID_RE.fullmatch(value) is None:
        raise ApiProblem(400, "invalid_request", "builtin_id has an invalid format.")
    return value


def _hosted_app_title(payload: dict[str, Any]) -> str:
    value = _required_string(payload, "title", min_length=1, max_length=80)
    if value != value.strip():
        raise ApiProblem(400, "invalid_request", "title must not have leading or trailing whitespace.")
    return value


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

    if method == "GET" and path == "/hosted/legal":
        return _json_response(200, legal_payload())

    if method == "GET" and path == "/hosted/builtins":
        return _json_response(200, {"builtins": _get_backend().list_builtin_templates()})

    if method == "POST" and path == "/hosted/register":
        payload = _json_body(event)
        _require_fields(
            payload,
            required={
                "login_id",
                "password",
                "terms_version",
                "privacy_version",
                "terms_accepted",
                "privacy_accepted",
            },
        )
        terms_version, privacy_version = _registration_legal_versions(payload)
        return _json_response(
            201,
            _get_backend().register(
                _login_id(payload),
                _password(payload, "password"),
                terms_version,
                privacy_version,
            ),
        )

    if method == "POST" and path == "/hosted/recover":
        payload = _json_body(event)
        _require_fields(payload, required={"login_id", "recovery_code", "new_password"})
        return _json_response(
            200,
            _get_backend().recover_account(
                _login_id(payload),
                _recovery_code(payload),
                _password(payload, "new_password"),
            ),
        )

    runtime_state_match = _RUNTIME_STATE_RE.fullmatch(path)
    if runtime_state_match is not None:
        token, key = runtime_state_match.groups()
        if method == "GET":
            return _json_response(200, _get_backend().get_runtime_state(token, key))
        if method == "POST":
            payload = _json_body(event)
            _require_fields(payload, required={"value"})
            return _json_response(
                200,
                _get_backend().set_runtime_state(token, key, payload["value"]),
            )
        if method == "DELETE":
            _get_backend().delete_runtime_state(token, key)
            return _empty_response()

    if method == "GET" and path == "/hosted/me":
        return _json_response(200, _get_backend().me(_auth_subject(event)))

    if method == "POST" and path == "/hosted/recovery-code":
        payload = _json_body(event)
        _require_fields(payload, required=set())
        return _json_response(200, _get_backend().rotate_recovery_code(_auth_subject(event)))

    if method == "DELETE" and path == "/hosted/account":
        _get_backend().delete_account(_auth_subject(event))
        return _empty_response()

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

    ownership_match = _GROUP_OWNER_RE.fullmatch(path)
    if ownership_match is not None and method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required={"user_id"})
        return _json_response(
            200,
            _get_backend().transfer_group_ownership(
                _auth_subject(event), ownership_match.group(1), _user_id(payload)
            ),
        )

    group_apps_match = _GROUP_APPS_RE.fullmatch(path)
    if group_apps_match is not None and method == "GET":
        return _json_response(
            200,
            {"apps": _get_backend().list_group_apps(_auth_subject(event), group_apps_match.group(1))},
        )

    app_install_match = _GROUP_APP_INSTALL_RE.fullmatch(path)
    if app_install_match is not None and method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required={"builtin_id"})
        return _json_response(
            201,
            _get_backend().install_builtin(
                _auth_subject(event), app_install_match.group(1), _builtin_id(payload)
            ),
        )

    app_fork_match = _GROUP_APP_FORK_RE.fullmatch(path)
    if app_fork_match is not None and method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required={"title"})
        group_id, app_id = app_fork_match.groups()
        return _json_response(
            201,
            _get_backend().fork_app(
                _auth_subject(event), group_id, app_id, _hosted_app_title(payload)
            ),
        )

    runtime_session_match = _RUNTIME_SESSION_RE.fullmatch(path)
    if runtime_session_match is not None and method == "POST":
        payload = _json_body(event)
        _require_fields(payload, required=set())
        group_id, app_id = runtime_session_match.groups()
        return _json_response(
            201,
            _get_backend().create_runtime_session(_auth_subject(event), group_id, app_id),
        )

    app_match = _GROUP_APP_RE.fullmatch(path)
    if app_match is not None and method == "DELETE":
        group_id, app_id = app_match.groups()
        _get_backend().delete_hosted_app(_auth_subject(event), group_id, app_id)
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

    group_match = _GROUP_RE.fullmatch(path)
    if group_match is not None and method == "DELETE":
        _get_backend().delete_group(_auth_subject(event), group_match.group(1))
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
