from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _User, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from phase4_backend import Phase4AwsBackend  # noqa: E402


class FakeDynamo:
    def __init__(self, items: list[dict[str, Any]] | None = None) -> None:
        self.items = items or []
        self.updated = False

    def query(self, **kwargs: Any) -> dict[str, Any]:
        del kwargs
        return {"Items": self.items}

    def update_item(self, **kwargs: Any) -> dict[str, Any]:
        del kwargs
        self.updated = True
        return {}


class FakeS3:
    pass


def _backend(dynamo: Any | None = None) -> Phase4AwsBackend:
    return Phase4AwsBackend(
        cognito=object(),
        dynamodb=dynamo or FakeDynamo(),
        s3=FakeS3(),
        user_pool_id="pool",
        app_client_id="client",
        table_name="table",
        upload_bucket="uploads",
        published_bucket="published",
    )


def _meta(*, status: str | None = None) -> dict[str, Any]:
    item = {
        "app_id": _string_attr("a" * 32),
        "group_id": _string_attr("c" * 32),
        "group_name": _string_attr("ねんね組"),
        "owner_user_id": _string_attr("1" * 32),
        "owner_login_id": _string_attr("student-demo"),
        "title": _string_attr("時間割"),
        "created_at": _string_attr("2026-08-17T00:00:00Z"),
    }
    if status is not None:
        item["status"] = _string_attr(status)
    return item


def _version(
    version_id: str,
    *,
    status: str,
    created_at: str,
    reviewed_at: str | None = None,
) -> dict[str, Any]:
    item = {
        "app_id": _string_attr("a" * 32),
        "version_id": _string_attr(version_id),
        "group_id": _string_attr("c" * 32),
        "group_name": _string_attr("ねんね組"),
        "owner_user_id": _string_attr("1" * 32),
        "owner_login_id": _string_attr("student-demo"),
        "title": _string_attr("時間割"),
        "filename": _string_attr("app.zip"),
        "status": _string_attr(status),
        "created_at": _string_attr(created_at),
    }
    if reviewed_at is not None:
        item["reviewed_at"] = _string_attr(reviewed_at)
        item["published_key"] = _string_attr("published/source.zip")
    return item


class Phase4BackendTests(unittest.TestCase):
    def test_missing_app_status_is_active_for_existing_phase2_data(self) -> None:
        self.assertEqual(Phase4AwsBackend._app_status(_meta()), "active")

    def test_lifecycle_list_numbers_versions_and_marks_latest_published(self) -> None:
        v1 = _version(
            "b" * 32,
            status="approved",
            created_at="2026-08-17T00:00:00Z",
            reviewed_at="2026-08-17T01:00:00Z",
        )
        v2 = _version(
            "d" * 32,
            status="approved",
            created_at="2026-08-17T02:00:00Z",
            reviewed_at="2026-08-17T03:00:00Z",
        )
        backend = _backend(FakeDynamo([v1, v2]))
        backend._user_by_auth_subject = lambda subject: _User(  # type: ignore[method-assign]
            "1" * 32, subject, "student-demo", "student", "active"
        )
        backend._app_meta_item = lambda app_id: _meta()  # type: ignore[method-assign]

        apps = backend.list_my_apps_lifecycle("sub")
        self.assertEqual(len(apps), 2)
        latest = next(app for app in apps if app["version_id"] == "d" * 32)
        older = next(app for app in apps if app["version_id"] == "b" * 32)
        self.assertEqual(latest["version_number"], 2)
        self.assertTrue(latest["is_latest_version"])
        self.assertTrue(latest["is_published"])
        self.assertFalse(older["is_published"])

    def test_new_version_is_blocked_while_review_is_pending(self) -> None:
        backend = _backend()
        student = _User("1" * 32, "sub", "student-demo", "student", "active")
        backend._user_by_auth_subject = lambda subject: student  # type: ignore[method-assign]
        backend._require_active_app = lambda app_id: _meta()  # type: ignore[method-assign]
        backend._require_active_membership = lambda user_id, group_id, role: "ねんね組"  # type: ignore[method-assign]
        backend._version_items = lambda app_id: [  # type: ignore[method-assign]
            _version("b" * 32, status="pending_review", created_at="2026-08-17T00:00:00Z")
        ]

        with self.assertRaises(ApiProblem) as caught:
            backend.upload_app_version("sub", "a" * 32, "update.zip", b"not-used")
        self.assertEqual(caught.exception.error, "unfinished_version_exists")

    def test_archive_refuses_app_with_pending_review(self) -> None:
        dynamo = FakeDynamo()
        backend = _backend(dynamo)
        student = _User("1" * 32, "sub", "student-demo", "student", "active")
        backend._user_by_auth_subject = lambda subject: student  # type: ignore[method-assign]
        backend._require_active_app = lambda app_id: _meta()  # type: ignore[method-assign]
        backend._require_active_membership = lambda user_id, group_id, role: "ねんね組"  # type: ignore[method-assign]
        backend._version_items = lambda app_id: [  # type: ignore[method-assign]
            _version("b" * 32, status="pending_review", created_at="2026-08-17T00:00:00Z")
        ]

        with self.assertRaises(ApiProblem) as caught:
            backend.archive_app("sub", "a" * 32)
        self.assertEqual(caught.exception.error, "review_in_progress")
        self.assertFalse(dynamo.updated)

    def test_old_approved_version_cannot_create_new_launch_token(self) -> None:
        backend = _backend()
        backend._require_active_app = lambda app_id: _meta()  # type: ignore[method-assign]
        backend._version_items = lambda app_id: [  # type: ignore[method-assign]
            _version(
                "b" * 32,
                status="approved",
                created_at="2026-08-17T00:00:00Z",
                reviewed_at="2026-08-17T01:00:00Z",
            ),
            _version(
                "d" * 32,
                status="approved",
                created_at="2026-08-17T02:00:00Z",
                reviewed_at="2026-08-17T03:00:00Z",
            ),
        ]

        with self.assertRaises(ApiProblem) as caught:
            backend.create_launch("sub", "a" * 32, "b" * 32)
        self.assertEqual(caught.exception.error, "old_version_not_published")


if __name__ == "__main__":
    unittest.main()
