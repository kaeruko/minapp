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
import hosted_preview_state_entry  # noqa: E402


class FakePreviewBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []

    def is_preview_runtime_session(self, token: str) -> bool:
        self.calls.append(("is_preview", token))
        return True

    def get_preview_runtime_state(
        self, token: str, key: str, *, user_state: bool
    ) -> dict[str, Any]:
        self.calls.append(("get", token, key, user_state))
        return {"key": key, "value": 7, "updated_at": "2026-09-06T09:00:00Z"}

    def set_preview_runtime_state(
        self, token: str, key: str, value: Any, *, user_state: bool
    ) -> dict[str, Any]:
        self.calls.append(("set", token, key, value, user_state))
        return {"key": key, "value": value, "updated_at": "2026-09-06T09:00:00Z"}

    def delete_preview_runtime_state(
        self, token: str, key: str, *, user_state: bool
    ) -> None:
        self.calls.append(("delete", token, key, user_state))


def event(method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {"http": {"method": method}},
        "headers": {},
    }
    if body is not None:
        result["headers"] = {"content-type": "application/json"}
        result["body"] = json.dumps(body)
    return result


class HostedPreviewStateEntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakePreviewBackend()
        hosted_preview_state_entry._BACKEND = self.backend
        self.token = "A" * 43
        self.path = f"/hosted/runtime/{self.token}/state/chapter"

    def tearDown(self) -> None:
        hosted_preview_state_entry._BACKEND = None

    def test_deployed_hosted_entry_routes_preview_shared_state(self) -> None:
        response = abuse_entry.hosted_lambda_handler(event("GET", self.path), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["value"], 7)
        self.assertEqual(
            self.backend.calls,
            [("is_preview", self.token), ("get", self.token, "chapter", False)],
        )

    def test_preview_interceptor_does_not_match_user_state(self) -> None:
        response = hosted_preview_state_entry.handle_request(
            event("GET", f"/hosted/runtime/{self.token}/user-state/chapter")
        )
        self.assertIsNone(response)
        self.assertEqual(self.backend.calls, [])


if __name__ == "__main__":
    unittest.main()
