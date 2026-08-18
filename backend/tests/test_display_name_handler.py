from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

import display_name_handler  # noqa: E402


class FakeBackend:
    def __init__(self) -> None:
        self.last_call: tuple[Any, ...] | None = None

    def get_my_display_name(self, subject: str) -> dict[str, Any]:
        self.last_call = ("get_self", subject)
        return {
            "user_id": "a" * 32,
            "login_id": "teacher-demo",
            "role": "teacher",
            "display_name": None,
        }

    def set_my_display_name(self, subject: str, display_name: str) -> dict[str, Any]:
        self.last_call = ("set_self", subject, display_name)
        return {
            "user_id": "a" * 32,
            "login_id": "teacher-demo",
            "role": "teacher",
            "display_name": display_name,
        }

    def list_group_display_names(self, subject: str, group_id: str) -> list[dict[str, Any]]:
        self.last_call = ("list_group", subject, group_id)
        return []

    def set_user_display_name(
        self,
        subject: str,
        user_id: str,
        display_name: str,
    ) -> dict[str, Any]:
        self.last_call = ("set_user", subject, user_id, display_name)
        return {
            "user_id": user_id,
            "login_id": "student-demo",
            "role": "student",
            "display_name": display_name,
        }


def _event(method: str, path: str, *, body: dict[str, Any] | None = None) -> dict[str, Any]:
    event: dict[str, Any] = {
        "rawPath": path,
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": "sub"}}},
        },
    }
    if body is not None:
        event["headers"] = {"content-type": "application/json"}
        event["body"] = json.dumps(body, ensure_ascii=False)
    return event


class DisplayNameHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        display_name_handler._BACKEND = self.backend  # type: ignore[assignment]

    def tearDown(self) -> None:
        display_name_handler._BACKEND = None

    def test_get_self_name(self) -> None:
        response = display_name_handler.lambda_handler(_event("GET", "/me/display-name"), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("get_self", "sub"))

    def test_patch_self_name(self) -> None:
        response = display_name_handler.lambda_handler(
            _event("PATCH", "/me/display-name", body={"display_name": "横田"}),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("set_self", "sub", "横田"))

    def test_patch_rejects_surrounding_whitespace(self) -> None:
        response = display_name_handler.lambda_handler(
            _event("PATCH", "/me/display-name", body={"display_name": " 横田"}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertIsNone(self.backend.last_call)

    def test_list_group_names(self) -> None:
        group_id = "b" * 32
        response = display_name_handler.lambda_handler(
            _event("GET", f"/groups/{group_id}/display-names"),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("list_group", "sub", group_id))

    def test_teacher_sets_student_name(self) -> None:
        user_id = "c" * 32
        response = display_name_handler.lambda_handler(
            _event(
                "PATCH",
                f"/users/{user_id}/display-name",
                body={"display_name": "山田 太郎"},
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.backend.last_call, ("set_user", "sub", user_id, "山田 太郎"))


if __name__ == "__main__":
    unittest.main()
