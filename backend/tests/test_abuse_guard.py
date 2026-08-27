from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import abuse_entry  # noqa: E402
import abuse_guard  # noqa: E402
import handler  # noqa: E402
import hosted_handler  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402


class ConditionalFailure(Exception):
    def __init__(self) -> None:
        super().__init__("conditional failed")
        self.response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeDynamo:
    def __init__(self, *, fail_condition: bool = False) -> None:
        self.fail_condition = fail_condition
        self.calls: list[dict[str, Any]] = []

    def update_item(self, **kwargs: Any) -> None:
        self.calls.append(kwargs)
        if self.fail_condition:
            raise ConditionalFailure()


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def login(self, login_id: str, password: str) -> dict[str, Any]:
        self.calls.append(("login", login_id, password))
        return {"state": "authenticated", "access_token": "token", "token_type": "Bearer", "expires_in": 3600}

    def register(
        self,
        login_id: str,
        password: str,
        terms_version: str,
        privacy_version: str,
    ) -> dict[str, Any]:
        self.calls.append(("register", login_id, password, terms_version, privacy_version))
        return {"user_id": "1" * 32, "login_id": login_id, "role": "user", "status": "active"}

    def recover_account(self, login_id: str, recovery_code: str, new_password: str) -> dict[str, Any]:
        self.calls.append(("recover", login_id, recovery_code, new_password))
        return {"login_id": login_id, "recovery_code": "2345-6789-ABCD-EFGH-JKLM"}


class FakeGuard:
    def __init__(self, *, reject: bool = False) -> None:
        self.reject = reject
        self.calls: list[tuple[str, str, str | None]] = []

    def check(self, action: str, *, source_ip: str, login_id: str | None = None) -> None:
        self.calls.append((action, source_ip, login_id))
        if self.reject:
            raise ApiProblem(429, "rate_limited", "too many")


def event(method: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "rawPath": path,
        "requestContext": {"http": {"method": method, "sourceIp": "203.0.113.10"}},
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def registration_body() -> dict[str, Any]:
    return {
        "login_id": "alice",
        "password": "secret12",
        "terms_version": TERMS_VERSION,
        "privacy_version": PRIVACY_VERSION,
        "terms_accepted": True,
        "privacy_accepted": True,
    }


class AbuseGuardTests(unittest.TestCase):
    def test_register_uses_only_hashed_subjects(self) -> None:
        dynamo = FakeDynamo()
        guard = abuse_guard.AbuseGuard(
            dynamodb=dynamo,
            table_name="minapp-hosted-dev-data-abuse",
            hash_salt="tenant-123",
            now_fn=lambda: 1_800_000_123,
        )
        guard.check("register", source_ip="203.0.113.10", login_id="alice")
        self.assertEqual(len(dynamo.calls), 3)
        serialized = json.dumps(dynamo.calls)
        self.assertNotIn("203.0.113.10", serialized)
        self.assertNotIn("alice", serialized)
        self.assertTrue(all(call["TableName"] == "minapp-hosted-dev-data-abuse" for call in dynamo.calls))

    def test_conditional_failure_becomes_rate_limited(self) -> None:
        guard = abuse_guard.AbuseGuard(
            dynamodb=FakeDynamo(fail_condition=True),
            table_name="abuse",
            hash_salt="tenant",
            now_fn=lambda: 1_800_000_000,
        )
        with self.assertRaises(ApiProblem) as caught:
            guard.check("login", source_ip="203.0.113.10", login_id="alice")
        self.assertEqual(caught.exception.status_code, 429)
        self.assertEqual(caught.exception.error, "rate_limited")

    def test_source_ip_is_required_and_validated(self) -> None:
        with self.assertRaisesRegex(ValueError, "sourceIp"):
            abuse_guard.source_ip_from_event({"requestContext": {"http": {"method": "POST"}}})
        self.assertEqual(
            abuse_guard.source_ip_from_event(
                {"requestContext": {"http": {"method": "POST", "sourceIp": "2001:0db8::1"}}}
            ),
            "2001:db8::1",
        )


class AbuseEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.guard = FakeGuard()
        self.original_get_guard = abuse_entry.get_abuse_guard
        abuse_entry.get_abuse_guard = lambda: self.guard
        self.api_backend = FakeBackend()
        self.hosted_backend = FakeBackend()
        handler._BACKEND = self.api_backend
        hosted_handler._BACKEND = self.hosted_backend

    def tearDown(self) -> None:
        abuse_entry.get_abuse_guard = self.original_get_guard
        handler._BACKEND = None
        hosted_handler._BACKEND = None

    def test_login_is_guarded_before_backend(self) -> None:
        response = abuse_entry.api_lambda_handler(
            event("POST", "/auth/login", {"login_id": "alice", "password": "secret12"}),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.guard.calls, [("login", "203.0.113.10", "alice")])
        self.assertEqual(self.api_backend.calls, [("login", "alice", "secret12")])

    def test_register_is_guarded_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event("POST", "/hosted/register", registration_body()),
            None,
        )
        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(self.guard.calls, [("register", "203.0.113.10", "alice")])
        self.assertEqual(
            self.hosted_backend.calls,
            [("register", "alice", "secret12", TERMS_VERSION, PRIVACY_VERSION)],
        )

    def test_invalid_legal_consent_does_not_consume_rate_limit(self) -> None:
        body = registration_body()
        body["terms_accepted"] = False
        response = abuse_entry.hosted_lambda_handler(
            event("POST", "/hosted/register", body),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.guard.calls, [])
        self.assertEqual(self.hosted_backend.calls, [])

    def test_recover_is_guarded_before_backend(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event(
                "POST",
                "/hosted/recover",
                {
                    "login_id": "alice",
                    "recovery_code": "2345-6789-ABCD-EFGH-JKLM",
                    "new_password": "newsecret12",
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.guard.calls, [("recover", "203.0.113.10", "alice")])
        self.assertEqual(
            self.hosted_backend.calls,
            [("recover", "alice", "2345-6789-ABCD-EFGH-JKLM", "newsecret12")],
        )

    def test_rate_limit_stops_backend_call(self) -> None:
        self.guard.reject = True
        response = abuse_entry.hosted_lambda_handler(
            event("POST", "/hosted/register", registration_body()),
            None,
        )
        self.assertEqual(response["statusCode"], 429)
        payload = json.loads(response["body"])
        self.assertEqual(payload["error"], "rate_limited")
        self.assertEqual(self.hosted_backend.calls, [])

    def test_missing_source_ip_fails_fast(self) -> None:
        bad_event = event("POST", "/auth/login", {"login_id": "alice", "password": "secret12"})
        del bad_event["requestContext"]["http"]["sourceIp"]
        with self.assertRaisesRegex(ValueError, "sourceIp"):
            abuse_entry.api_lambda_handler(bad_event, None)


if __name__ == "__main__":
    unittest.main()
