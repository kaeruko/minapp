from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_handler  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def register(
        self,
        login_id: str,
        password: str,
        terms_version: str,
        privacy_version: str,
    ) -> dict[str, Any]:
        self.calls.append(("register", login_id, password, terms_version, privacy_version))
        return {
            "user_id": "1" * 32,
            "login_id": login_id,
            "role": "user",
            "status": "active",
            "legal": {
                "terms_version": terms_version,
                "privacy_version": privacy_version,
                "accepted_at": "2026-08-28T00:00:00Z",
            },
        }

    def me(self, auth_subject: str) -> dict[str, Any]:
        self.calls.append(("me", auth_subject))
        return {"user": {"user_id": "1" * 32, "login_id": "alice", "role": "user", "status": "active"}, "groups": []}

    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]:
        self.calls.append(("list_groups", auth_subject))
        return []

    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]:
        self.calls.append(("create_group", auth_subject, name))
        return {"group_id": "2" * 32, "name": name, "role": "owner", "status": "active"}

    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, str]]:
        self.calls.append(("list_members", auth_subject, group_id))
        return []

    def create_invite(self, auth_subject: str, group_id: str) -> dict[str, Any]:
        self.calls.append(("create_invite", auth_subject, group_id))
        return {"group_id": group_id, "code": "ABCD-EFGH-JKLM", "expires_at": "2026-09-03T00:00:00Z", "valid_for_seconds": 604800}

    def revoke_invite(self, auth_subject: str, group_id: str) -> None:
        self.calls.append(("revoke_invite", auth_subject, group_id))

    def join_group(self, auth_subject: str, invite_code: str) -> dict[str, Any]:
        self.calls.append(("join_group", auth_subject, invite_code))
        return {"group_id": "2" * 32, "name": "月影荘", "role": "member", "status": "active"}

    def leave_group(self, auth_subject: str, group_id: str) -> None:
        self.calls.append(("leave_group", auth_subject, group_id))

    def remove_member(self, auth_subject: str, group_id: str, user_id: str) -> None:
        self.calls.append(("remove_member", auth_subject, group_id, user_id))


def event(method: str, path: str, *, body: dict[str, Any] | None = None, auth: bool = False) -> dict[str, Any]:
    request_context: dict[str, Any] = {"http": {"method": method}}
    if auth:
        request_context["authorizer"] = {"jwt": {"claims": {"sub": "sub-alice"}}}
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": request_context,
        "headers": {},
    }
    if body is not None:
        result["headers"] = {"content-type": "application/json"}
        result["body"] = json.dumps(body, ensure_ascii=False)
    return result


def registration_body(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "login_id": "alice",
        "password": "secret12",
        "terms_version": TERMS_VERSION,
        "privacy_version": PRIVACY_VERSION,
        "terms_accepted": True,
        "privacy_accepted": True,
    }
    body.update(overrides)
    return body


class HostedHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        hosted_handler._BACKEND = self.backend

    def tearDown(self) -> None:
        hosted_handler._BACKEND = None

    def test_legal_documents_are_public_and_versioned(self) -> None:
        response = hosted_handler.lambda_handler(event("GET", "/hosted/legal"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["terms"]["version"], TERMS_VERSION)
        self.assertEqual(payload["privacy"]["version"], PRIVACY_VERSION)
        self.assertIn("zero tolerance", payload["terms"]["body"])
        self.assertIn("Amazon Web Services", payload["privacy"]["body"])
        self.assertEqual(self.backend.calls, [])

    def test_register_requires_current_legal_consent(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/register", body=registration_body()),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(
            self.backend.calls,
            [("register", "alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)],
        )

    def test_register_rejects_missing_legal_fields(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/register", body={"login_id": "alice", "password": "secret12"}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.backend.calls, [])

    def test_register_rejects_false_terms_acceptance(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/register", body=registration_body(terms_accepted=False)),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        payload = json.loads(response["body"])
        self.assertEqual(payload["error"], "terms_not_accepted")
        self.assertEqual(self.backend.calls, [])

    def test_register_rejects_stale_terms_version(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/register", body=registration_body(terms_version="old-terms")),
            None,
        )
        self.assertEqual(response["statusCode"], 409)
        payload = json.loads(response["body"])
        self.assertEqual(payload["error"], "terms_version_outdated")
        self.assertEqual(self.backend.calls, [])

    def test_unknown_register_field_fails_closed(self) -> None:
        response = hosted_handler.lambda_handler(
            event(
                "POST",
                "/hosted/register",
                body=registration_body(email="x@example.com"),
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        payload = json.loads(response["body"])
        self.assertEqual(payload["error"], "invalid_request")
        self.assertEqual(self.backend.calls, [])

    def test_create_group_uses_authenticated_subject(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/groups", body={"name": "月影荘"}, auth=True),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.backend.calls, [("create_group", "sub-alice", "月影荘")])

    def test_join_group_passes_invite_code(self) -> None:
        response = hosted_handler.lambda_handler(
            event("POST", "/hosted/groups/join", body={"code": "ABCD-EFGH-JKLM"}, auth=True),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.backend.calls, [("join_group", "sub-alice", "ABCD-EFGH-JKLM")])

    def test_invite_rotation_route_requires_empty_json_object(self) -> None:
        group_id = "2" * 32
        response = hosted_handler.lambda_handler(
            event("POST", f"/hosted/groups/{group_id}/invite", body={}, auth=True),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.backend.calls, [("create_invite", "sub-alice", group_id)])

    def test_leave_route_returns_no_content(self) -> None:
        group_id = "2" * 32
        response = hosted_handler.lambda_handler(
            event("DELETE", f"/hosted/groups/{group_id}/membership", auth=True),
            None,
        )
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(self.backend.calls, [("leave_group", "sub-alice", group_id)])

    def test_missing_authorizer_is_rejected(self) -> None:
        response = hosted_handler.lambda_handler(event("GET", "/hosted/me"), None)
        self.assertEqual(response["statusCode"], 401)
        payload = json.loads(response["body"])
        self.assertEqual(payload["error"], "unauthorized")


if __name__ == "__main__":
    unittest.main()
