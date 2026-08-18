from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _User, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from phase4_backend import Phase4AwsBackend  # noqa: E402
from phase4_moderation_backend import Phase4ModerationAwsBackend  # noqa: E402


def _backend() -> Phase4ModerationAwsBackend:
    return Phase4ModerationAwsBackend(
        cognito=object(),
        dynamodb=object(),
        s3=object(),
        user_pool_id="pool",
        app_client_id="client",
        table_name="table",
        upload_bucket="uploads",
        published_bucket="published",
    )


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
        "source_key": _string_attr("drafts/source.zip"),
        "sha256": _string_attr("f" * 64),
        "created_at": _string_attr(created_at),
    }
    if reviewed_at is not None:
        item["reviewed_at"] = _string_attr(reviewed_at)
        item["published_key"] = _string_attr("published/source.zip")
    return item


def _public_version(version_id: str, status: str, reviewed_at: str) -> dict[str, Any]:
    return {
        "app_id": "a" * 32,
        "version_id": version_id,
        "group_id": "c" * 32,
        "group_name": "ねんね組",
        "owner_user_id": "1" * 32,
        "owner_login_id": "student-demo",
        "title": "時間割",
        "filename": "app.zip",
        "status": status,
        "created_at": "2026-08-17T00:00:00Z",
        "reviewed_at": reviewed_at,
        "version_number": 1,
        "version_count": 2,
        "is_latest_version": False,
        "is_published": status == "approved",
        "app_status": "active",
    }


class Phase4ModerationBackendTests(unittest.TestCase):
    def test_latest_publication_decision_includes_unpublished_marker(self) -> None:
        approved = _version(
            "b" * 32,
            status="approved",
            created_at="2026-08-17T00:00:00Z",
            reviewed_at="2026-08-17T01:00:00Z",
        )
        unpublished = _version(
            "d" * 32,
            status="unpublished",
            created_at="2026-08-17T02:00:00Z",
            reviewed_at="2026-08-17T03:00:00Z",
        )
        latest = Phase4ModerationAwsBackend._latest_publication_decision([approved, unpublished])
        self.assertIsNotNone(latest)
        self.assertEqual(latest["version_id"], _string_attr("d" * 32))

    def test_reject_transitions_pending_review_to_rejected(self) -> None:
        backend = _backend()
        teacher = _User("2" * 32, "sub", "teacher-demo", "teacher", "active")
        version = _version("b" * 32, status="pending_review", created_at="2026-08-17T00:00:00Z")
        backend._require_active_app = lambda app_id: {}  # type: ignore[method-assign]
        backend._user_by_auth_subject = lambda subject: teacher  # type: ignore[method-assign]
        backend._version_item = lambda app_id, version_id: version  # type: ignore[method-assign]
        backend._require_teacher_membership = lambda user_id, group_id: None  # type: ignore[method-assign]
        transition: dict[str, Any] = {}

        def capture_transition(item: dict[str, Any], **kwargs: Any) -> None:
            transition.update(kwargs)

        backend._transition_version = capture_transition  # type: ignore[method-assign]
        result = backend.reject_app("sub", "a" * 32, "b" * 32)
        self.assertEqual(transition["expected_status"], "pending_review")
        self.assertEqual(transition["new_status"], "rejected")
        self.assertEqual(result["status"], "rejected")

    def test_unpublish_only_accepts_latest_published_version(self) -> None:
        backend = _backend()
        teacher = _User("2" * 32, "sub", "teacher-demo", "teacher", "active")
        older = _version(
            "b" * 32,
            status="approved",
            created_at="2026-08-17T00:00:00Z",
            reviewed_at="2026-08-17T01:00:00Z",
        )
        newer = _version(
            "d" * 32,
            status="approved",
            created_at="2026-08-17T02:00:00Z",
            reviewed_at="2026-08-17T03:00:00Z",
        )
        backend._require_active_app = lambda app_id: {}  # type: ignore[method-assign]
        backend._user_by_auth_subject = lambda subject: teacher  # type: ignore[method-assign]
        backend._version_item = lambda app_id, version_id: older  # type: ignore[method-assign]
        backend._require_teacher_membership = lambda user_id, group_id: None  # type: ignore[method-assign]
        backend._version_items = lambda app_id: [older, newer]  # type: ignore[method-assign]

        with self.assertRaises(ApiProblem) as caught:
            backend.unpublish_app("sub", "a" * 32, "b" * 32)
        self.assertEqual(caught.exception.error, "old_version_not_published")

    def test_lifecycle_does_not_fall_back_after_publication_is_stopped(self) -> None:
        backend = _backend()
        older = _public_version("b" * 32, "approved", "2026-08-17T01:00:00Z")
        newer = _public_version("d" * 32, "unpublished", "2026-08-17T03:00:00Z")
        newer["version_number"] = 2
        newer["is_latest_version"] = True
        with patch.object(Phase4AwsBackend, "list_my_apps_lifecycle", return_value=[newer, older]):
            apps = backend.list_my_apps_lifecycle("sub")
        self.assertFalse(any(app["is_published"] for app in apps))

    def test_mobile_catalog_hides_app_after_unpublish(self) -> None:
        backend = _backend()
        candidate = _public_version("b" * 32, "approved", "2026-08-17T01:00:00Z")
        unpublished = _version(
            "b" * 32,
            status="unpublished",
            created_at="2026-08-17T00:00:00Z",
            reviewed_at="2026-08-17T01:00:00Z",
        )
        backend._version_items = lambda app_id: [unpublished]  # type: ignore[method-assign]
        with patch.object(Phase4AwsBackend, "list_mobile_apps", return_value=[candidate]):
            apps = backend.list_mobile_apps("sub")
        self.assertEqual(apps, [])

    def test_stale_launch_is_blocked_after_unpublish(self) -> None:
        backend = _backend()
        unpublished = _version(
            "b" * 32,
            status="unpublished",
            created_at="2026-08-17T00:00:00Z",
            reviewed_at="2026-08-17T01:00:00Z",
        )
        backend._require_active_app = lambda app_id: {}  # type: ignore[method-assign]
        backend._version_items = lambda app_id: [unpublished]  # type: ignore[method-assign]
        with self.assertRaises(ApiProblem) as caught:
            backend.create_launch("sub", "a" * 32, "b" * 32)
        self.assertEqual(caught.exception.error, "app_unpublished")


if __name__ == "__main__":
    unittest.main()
