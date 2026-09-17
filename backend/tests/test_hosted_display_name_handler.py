from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import hosted_display_name_handler  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []
        self.display_name: str | None = None

    def get_my_display_name(self, auth_subject: str) -> dict[str, Any]:
        self.calls.append(("get", auth_subject))
        return {
            "user_id": "1" * 32,
            "login_id": "alice",
            "role": "user",
            "display_name": self.display_name,
        }

    def set_my_display_name(
        self,
        auth_subject: str,
        display_name: str,
    ) -> dict[str, Any]:
        self.calls.append(("set", auth_subject, display_name))
        self.display_name = display_name
        return {
            "user_id": "1" * 32,
            "login_id": "alice",
            "role": "user",
            "display_name": display_name,
        }


def event(method: str, *, body: dict[str, Any] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "rawPath": "/hosted/me/display-name",
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub-alice"}}},
        },
    }
    if body is not None:
        result["body"] = json.dumps(body)
    return result


class HostedDisplayNameHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        self.previous = hosted_display_name_handler._BACKEND
        hosted_display_name_handler._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        hosted_display_name_handler._BACKEND = self.previous

    def test_get_returns_optional_display_name(self) -> None:
        response = hosted_display_name_handler.handle_request(event("GET"))
        self.assertIsNotNone(response)
        assert response is not None
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["display_name"], None)
        self.assertEqual(self.backend.calls, [("get", "sub-alice")])

    def test_patch_updates_display_name(self) -> None:
        response = hosted_display_name_handler.handle_request(
            event("PATCH", body={"display_name": "ねんね"})
        )
        self.assertIsNotNone(response)
        assert response is not None
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"])["display_name"], "ねんね")
        self.assertEqual(self.backend.calls, [("set", "sub-alice", "ねんね")])

    def test_other_path_is_not_claimed(self) -> None:
        other = event("GET")
        other["rawPath"] = "/hosted/me"
        self.assertIsNone(hosted_display_name_handler.handle_request(other))


if __name__ == "__main__":
    unittest.main()
