from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _User, _string_attr  # noqa: E402
from display_name_backend import DisplayNameAwsBackend  # noqa: E402


class FakeDynamo:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}
        self.query_items: list[dict[str, Any]] = []
        self.last_put: dict[str, Any] | None = None

    def get_item(self, **kwargs: Any) -> dict[str, Any]:
        key = kwargs["Key"]
        pk = key["pk"]["S"]
        sk = key["sk"]["S"]
        item = self.items.get((pk, sk))
        return {} if item is None else {"Item": item}

    def put_item(self, **kwargs: Any) -> dict[str, Any]:
        self.last_put = kwargs
        item = kwargs["Item"]
        self.items[(item["pk"]["S"], item["sk"]["S"])] = item
        return {}

    def query(self, **kwargs: Any) -> dict[str, Any]:
        del kwargs
        return {"Items": list(self.query_items)}


class FakeS3:
    pass


def _backend(dynamo: FakeDynamo | None = None) -> DisplayNameAwsBackend:
    return DisplayNameAwsBackend(
        cognito=object(),
        dynamodb=dynamo or FakeDynamo(),
        s3=FakeS3(),
        user_pool_id="pool",
        app_client_id="client",
        table_name="table",
        upload_bucket="uploads",
        published_bucket="published",
    )


def _user(user_id: str, role: str, login_id: str) -> _User:
    return _User(user_id, f"sub-{user_id}", login_id, role, "active")


class DisplayNameBackendTests(unittest.TestCase):
    def test_self_name_is_optional_then_persisted(self) -> None:
        dynamo = FakeDynamo()
        backend = _backend(dynamo)
        teacher = _user("1" * 32, "teacher", "teacher-demo")
        backend._user_by_auth_subject = lambda subject: teacher  # type: ignore[method-assign]

        before = backend.get_my_display_name("sub")
        self.assertIsNone(before["display_name"])

        after = backend.set_my_display_name("sub", "横田")
        self.assertEqual(after["display_name"], "横田")
        self.assertEqual(backend.get_my_display_name("sub")["display_name"], "横田")
        self.assertIsNotNone(dynamo.last_put)

    def test_teacher_can_set_shared_student_name(self) -> None:
        backend = _backend()
        teacher = _user("1" * 32, "teacher", "teacher-demo")
        student = _user("2" * 32, "student", "student-demo")
        backend._user_by_auth_subject = lambda subject: teacher  # type: ignore[method-assign]
        backend._user_by_id = lambda user_id: student  # type: ignore[method-assign]
        shared_calls: list[tuple[str, str]] = []
        backend._require_shared_teacher_group = lambda teacher_id, student_id: shared_calls.append(  # type: ignore[method-assign]
            (teacher_id, student_id)
        )

        result = backend.set_user_display_name("sub", student.user_id, "山田 太郎")
        self.assertEqual(result["display_name"], "山田 太郎")
        self.assertEqual(shared_calls, [(teacher.user_id, student.user_id)])

    def test_group_name_list_includes_optional_display_names(self) -> None:
        dynamo = FakeDynamo()
        backend = _backend(dynamo)
        teacher = _user("1" * 32, "teacher", "teacher-demo")
        backend._user_by_auth_subject = lambda subject: teacher  # type: ignore[method-assign]
        backend._require_teacher_membership = lambda user_id, group_id: "火曜"  # type: ignore[method-assign]
        dynamo.query_items = [
            {
                "user_id": _string_attr("2" * 32),
                "login_id": _string_attr("student-demo"),
                "role": _string_attr("student"),
                "status": _string_attr("active"),
            }
        ]
        dynamo.items[(f"USER#{'2' * 32}", "DISPLAY_NAME")] = {
            "entity": _string_attr("user_display_name"),
            "display_name": _string_attr("鈴木 花子"),
        }

        members = backend.list_group_display_names("sub", "a" * 32)
        self.assertEqual(members[0]["display_name"], "鈴木 花子")

    def test_app_owner_decoration_falls_back_when_name_missing(self) -> None:
        backend = _backend()
        app = {"owner_user_id": "2" * 32, "owner_login_id": "student-demo"}
        self.assertNotIn("owner_display_name", backend._decorate_app_owner(app))

    def test_app_owner_decoration_adds_current_name(self) -> None:
        dynamo = FakeDynamo()
        backend = _backend(dynamo)
        dynamo.items[(f"USER#{'2' * 32}", "DISPLAY_NAME")] = {
            "entity": _string_attr("user_display_name"),
            "display_name": _string_attr("佐藤 一郎"),
        }
        app = {"owner_user_id": "2" * 32, "owner_login_id": "student-demo"}
        decorated = backend._decorate_app_owner(app)
        self.assertEqual(decorated["owner_display_name"], "佐藤 一郎")
        self.assertEqual(decorated["owner_login_id"], "student-demo")


if __name__ == "__main__":
    unittest.main()
