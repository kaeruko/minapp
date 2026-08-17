from __future__ import annotations

import hashlib
import io
import sys
import time
import unittest
import zipfile
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _User, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from phase2_backend import _number_attr  # noqa: E402
from phase3_backend import LAUNCH_TTL_SECONDS, Phase3AwsBackend  # noqa: E402


class FakeDynamo:
    def __init__(self, items: list[dict[str, Any]]) -> None:
        self.items = items

    def query(self, **kwargs: Any) -> dict[str, Any]:
        del kwargs
        return {"Items": self.items}


class BytesBody:
    def __init__(self, data: bytes) -> None:
        self.data = data

    def read(self, size: int) -> bytes:
        return self.data[:size]


class FakeS3:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.last_bucket: str | None = None

    def get_object(self, *, Bucket: str, Key: str) -> dict[str, Any]:
        del Key
        self.last_bucket = Bucket
        return {"Body": BytesBody(self.data)}


def _version_item(*, status: str = "approved") -> dict[str, Any]:
    return {
        "pk": _string_attr(f"APP#{'a' * 32}"),
        "sk": _string_attr(f"VERSION#{'b' * 32}"),
        "entity": _string_attr("app_version"),
        "app_id": _string_attr("a" * 32),
        "version_id": _string_attr("b" * 32),
        "group_id": _string_attr("c" * 32),
        "group_name": _string_attr("ねんね組"),
        "owner_user_id": _string_attr("d" * 32),
        "owner_login_id": _string_attr("student-demo"),
        "title": _string_attr("時間割"),
        "filename": _string_attr("app.zip"),
        "status": _string_attr(status),
        "source_key": _string_attr("draft/source.zip"),
        "published_key": _string_attr("groups/c/apps/a/source.zip"),
        "sha256": _string_attr("0" * 64),
        "files_json": _string_attr('["index.html"]'),
        "created_at": _string_attr("2026-08-17T00:00:00Z"),
        "reviewed_at": _string_attr("2026-08-17T01:00:00Z"),
    }


def _backend(*, dynamo: Any | None = None, s3: Any | None = None) -> Phase3AwsBackend:
    return Phase3AwsBackend(
        cognito=object(),
        dynamodb=dynamo or FakeDynamo([]),
        s3=s3 or FakeS3(b""),
        user_pool_id="pool",
        app_client_id="client",
        table_name="table",
        upload_bucket="uploads",
        published_bucket="published",
    )


class Phase3BackendTests(unittest.TestCase):
    def test_catalog_only_returns_approved_apps_from_active_groups(self) -> None:
        backend = _backend(dynamo=FakeDynamo([_version_item(), _version_item(status="pending_review")]))
        user = _User("1" * 32, "sub", "student-demo", "student", "active")
        backend._user_by_auth_subject = lambda auth_subject: user  # type: ignore[method-assign]
        backend._membership_items_for_user = lambda user_id: [  # type: ignore[method-assign]
            {
                "group_id": _string_attr("c" * 32),
                "group_name": _string_attr("ねんね組"),
                "role": _string_attr("student"),
                "status": _string_attr("active"),
            }
        ]
        apps = backend.list_mobile_apps("sub")
        self.assertEqual(len(apps), 1)
        self.assertEqual(apps[0]["status"], "approved")

    def test_create_launch_requires_approved_version(self) -> None:
        backend = _backend()
        user = _User("1" * 32, "sub", "student-demo", "student", "active")
        backend._user_by_auth_subject = lambda auth_subject: user  # type: ignore[method-assign]
        backend._version_item = lambda app_id, version_id: _version_item(status="pending_review")  # type: ignore[method-assign]
        with self.assertRaises(ApiProblem) as caught:
            backend.create_launch("sub", "a" * 32, "b" * 32)
        self.assertEqual(caught.exception.error, "app_not_published")

    def test_create_launch_records_short_lived_token(self) -> None:
        backend = _backend()
        user = _User("1" * 32, "sub", "student-demo", "student", "active")
        version = _version_item()
        version["sha256"] = _string_attr("f" * 64)
        captured: list[dict[str, Any]] = []
        backend._user_by_auth_subject = lambda auth_subject: user  # type: ignore[method-assign]
        backend._version_item = lambda app_id, version_id: version  # type: ignore[method-assign]
        backend._require_active_membership = lambda user_id, group_id, role: "ねんね組"  # type: ignore[method-assign]
        backend._transact_put_new = lambda items: captured.extend(items)  # type: ignore[method-assign]
        before = int(time.time())
        result = backend.create_launch("sub", "a" * 32, "b" * 32)
        self.assertEqual(result["expires_in"], LAUNCH_TTL_SECONDS)
        self.assertGreaterEqual(int(captured[0]["expires_at"]["N"]), before + LAUNCH_TTL_SECONDS)

    def test_launch_file_reads_published_bucket_and_checks_hash(self) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("index.html", "<h1>わん</h1>")
        data = buffer.getvalue()
        s3 = FakeS3(data)
        backend = _backend(s3=s3)
        item = {
            "published_key": _string_attr("groups/c/apps/a/source.zip"),
            "sha256": _string_attr(hashlib.sha256(data).hexdigest()),
            "expires_at": _number_attr(int(time.time()) + 600),
        }
        backend._get_item = lambda pk, sk: item  # type: ignore[method-assign]
        content, content_type = backend.get_launch_file("token", "index.html")
        self.assertEqual(content.decode("utf-8"), "<h1>わん</h1>")
        self.assertEqual(content_type, "text/html; charset=utf-8")
        self.assertEqual(s3.last_bucket, "published")


if __name__ == "__main__":
    unittest.main()
