from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import handler  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def login(self, login_id: str, password: str) -> dict[str, Any]:
        self.last_call = ("login", login_id, password)
        return {"state": "authenticated", "access_token": "token", "token_type": "Bearer", "expires_in": 3600}

    def complete_new_password(self, login_id: str, new_password: str, session: str) -> dict[str, Any]:
        self.last_call = ("change", login_id, new_password, session)
        return {"state": "authenticated", "access_token": "token2", "token_type": "Bearer", "expires_in": 3600}

    def me(self, auth_subject: str) -> dict[str, Any]:
        self.last_call = ("me", auth_subject)
        return {"user": {"user_id": "a" * 32}, "groups": []}

    def list_groups(self, auth_subject: str) -> list[dict[str, Any]]:
        self.last_call = ("groups", auth_subject)
        return []

    def create_group(self, auth_subject: str, name: str) -> dict[str, Any]:
        self.last_call = ("create_group", auth_subject, name)
        return {"group_id": "b" * 32, "name": name, "role": "teacher", "status": "active"}

    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        self.last_call = ("members", auth_subject, group_id)
        return []

    def create_student(self, auth_subject: str, group_id: str) -> dict[str, Any]:
        self.last_call = ("create_student", auth_subject, group_id)
        return {"user_id": "c" * 32, "login_id": "student-12345678", "temporary_password": "ExamplePassword1", "group_id": group_id, "role": "student"}

    def reset_student_password(self, auth_subject: str, user_id: str) -> dict[str, Any]:
        self.last_call = ("reset", auth_subject, user_id)
        return {"user_id": user_id, "login_id": "student-12345678", "temporary_password": "AnotherPassword1"}

    def remove_member(self, auth_subject: str, group_id: str, user_id: str) -> None:
        self.last_call = ("remove", auth_subject, group_id, user_id)


def _event(method: str, path: str, *, body: dict[str, Any] | None = None, subject: str | None = None) -> dict[str, Any]:
    request_context: dict[str, Any] = {"http": {"method": method}}
    if subject is not None:
        request_context["authorizer"] = {"jwt": {"claims": {"sub": subject}}}
    event: dict[str, Any] = {"rawPath": path, "requestContext": request_context}
    if body is not None:
        event["headers"] = {"content-type": "application/json"}
        event["body"] = json.dumps(body)
    return event


class HandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        handler._BACKEND = self.backend

    def tearDown(self) -> None:
        handler._BACKEND = None

    def test_health(self) -> None:
        response = handler.lambda_handler(_event("GET", "/health"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["service"], "minapp-api")
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["version"], "0.3.0")

    def test_unknown_route_is_404_without_auth(self) -> None:
        response = handler.lambda_handler(_event("GET", "/unknown"), None)
        self.assertEqual(response["statusCode"], 404)

    def test_malformed_event_fails_fast(self) -> None:
        with self.assertRaisesRegex(ValueError, "requestContext"):
            handler.lambda_handler({"rawPath": "/health"}, None)

    def test_login_rejects_unknown_fields(self) -> None:
        response = handler.lambda_handler(_event("POST", "/auth/login", body={"login_id": "student-12345678", "password": "Password123", "unexpected": True}), None)
        self.assertEqual(response["statusCode"], 400)
        self.assertIn("Unknown field", json.loads(response["body"])["message"])

    def test_login_calls_backend(self) -> None:
        response = handler.lambda_handler(_event("POST", "/auth/login", body={"login_id": "student-12345678", "password": "Password123"}), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("login", "student-12345678", "Password123"))

    def test_login_accepts_cognito_minimum_password_length(self) -> None:
        response = handler.lambda_handler(_event("POST", "/auth/login", body={"login_id": "teacher-admin", "password": "aaaaaa"}), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("login", "teacher-admin", "aaaaaa"))

    def test_login_rejects_password_shorter_than_cognito_minimum(self) -> None:
        response = handler.lambda_handler(_event("POST", "/auth/login", body={"login_id": "teacher-admin", "password": "aaaaa"}), None)
        self.assertEqual(response["statusCode"], 400)
        self.assertIn("between 6 and 128", json.loads(response["body"])["message"])
        self.assertIsNone(self.backend.last_call)

    def test_protected_route_requires_authorizer_claims(self) -> None:
        response = handler.lambda_handler(_event("GET", "/me"), None)
        self.assertEqual(response["statusCode"], 401)

    def test_create_group_uses_authenticated_subject(self) -> None:
        response = handler.lambda_handler(_event("POST", "/groups", body={"name": "6年2組"}, subject="cognito-sub"), None)
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.backend.last_call, ("create_group", "cognito-sub", "6年2組"))

    def test_create_student_requires_empty_json_object(self) -> None:
        group_id = "a" * 32
        response = handler.lambda_handler(_event("POST", f"/groups/{group_id}/students", body={"login_id": "student-manual"}, subject="teacher-sub"), None)
        self.assertEqual(response["statusCode"], 400)
        self.assertIn("Unknown field", json.loads(response["body"])["message"])

    def test_remove_member_returns_204(self) -> None:
        group_id = "a" * 32
        user_id = "b" * 32
        response = handler.lambda_handler(_event("DELETE", f"/groups/{group_id}/members/{user_id}", subject="teacher-sub"), None)
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(self.backend.last_call, ("remove", "teacher-sub", group_id, user_id))


if __name__ == "__main__":
    unittest.main()
