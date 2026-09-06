from __future__ import annotations

import json
import pathlib
import sys
import unittest
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

import abuse_entry  # noqa: E402
import hosted_user_state_entry  # noqa: E402


class FakeUserStateBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def get_runtime_user_state(self, token: str, key: str) -> dict[str, Any]:
        self.calls.append(("get", token, key))
        return {"key": key, "value": {"scene": "start"}, "updated_at": "2026-09-06T08:00:00Z"}

    def set_runtime_user_state(
        self, token: str, key: str, value: Any
    ) -> dict[str, Any]:
        self.calls.append(("set", token, key, value))
        return {"key": key, "value": value, "updated_at": "2026-09-06T08:00:00Z"}

    def delete_runtime_user_state(self, token: str, key: str) -> None:
        self.calls.append(("delete", token, key))


def event(method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {"http": {"method": method}},
        "headers": {},
    }
    if body is not None:
        result["body"] = json.dumps(body)
    return result


class HostedUserStateEntryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeUserStateBackend()
        hosted_user_state_entry._BACKEND = self.backend
        self.token = "A" * 43
        self.path = f"/hosted/runtime/{self.token}/user-state/progress"

    def tearDown(self) -> None:
        hosted_user_state_entry._BACKEND = None

    def test_deployed_hosted_entry_routes_user_state_get(self) -> None:
        response = abuse_entry.hosted_lambda_handler(event("GET", self.path), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.calls, [("get", self.token, "progress")])

    def test_deployed_hosted_entry_routes_user_state_set(self) -> None:
        value = {"scene": "start", "event": "evt-1"}
        response = abuse_entry.hosted_lambda_handler(
            event("POST", self.path, {"value": value}),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.calls, [("set", self.token, "progress", value)])

    def test_deployed_hosted_entry_routes_user_state_delete(self) -> None:
        response = abuse_entry.hosted_lambda_handler(event("DELETE", self.path), None)
        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(response["body"], "")
        self.assertEqual(self.backend.calls, [("delete", self.token, "progress")])

    def test_set_rejects_extra_fields_instead_of_ignoring_them(self) -> None:
        response = abuse_entry.hosted_lambda_handler(
            event("POST", self.path, {"value": 1, "user_id": "attacker"}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        body = json.loads(response["body"])
        self.assertEqual(body["error"], "invalid_request")
        self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
