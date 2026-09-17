from __future__ import annotations

import hashlib
import io
import json
import sys
import unittest
import zipfile
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from aws_backend import _item_string, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
from hosted_platform_backend import _number_attr  # noqa: E402
from hosted_upload import create_uploaded_app  # noqa: E402


OWNER_ID = "1" * 32
GROUP_ID = "2" * 32
PACKAGE_A = "a" * 32
PACKAGE_B = "b" * 32


def make_zip(html: str, package_id: str | None = None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("index.html", html)
        if package_id is not None:
            archive.writestr(
                "minapp-package.json",
                json.dumps(
                    {"schema_version": 1, "package_id": package_id},
                    separators=(",", ":"),
                ),
            )
    return buffer.getvalue()


class FakeUploadBackend:
    def __init__(self) -> None:
        self._upload_bucket = "uploads"
        self._app_meta: dict[str, dict[str, object]] = {}
        self._group_items: list[dict[str, object]] = []
        self.update_calls: list[tuple[str, int]] = []
        self.put_count = 0

    def _user_by_auth_subject(self, auth_subject: str) -> SimpleNamespace:
        if auth_subject != "subject":
            raise AssertionError(auth_subject)
        return SimpleNamespace(user_id=OWNER_ID)

    def _require_active_membership(self, user_id: str, group_id: str) -> None:
        if user_id != OWNER_ID or group_id != GROUP_ID:
            raise AssertionError((user_id, group_id))

    def _require_app_capacity(self, group_id: str) -> None:
        if group_id != GROUP_ID:
            raise AssertionError(group_id)
        if len(self._group_items) >= 20:
            raise AssertionError("test capacity exceeded")

    def _group_app_items(self, group_id: str) -> list[dict[str, object]]:
        if group_id != GROUP_ID:
            raise AssertionError(group_id)
        return self._group_items

    def _require_app_in_group(self, app_id: str, group_id: str) -> dict[str, object]:
        if group_id != GROUP_ID:
            raise AssertionError(group_id)
        for item in self._group_items:
            if _item_string(item, "app_id") == app_id:
                return item
        raise AssertionError(f"missing app {app_id}")

    def _draft_source_key(self, group_id: str, app_id: str, revision: int) -> str:
        return f"draft/{group_id}/{app_id}/{revision}.zip"

    def _put_immutable_zip(self, **kwargs: object) -> str:
        self.put_count += 1
        return f"version-{self.put_count}"

    def _source_manifest(self, **kwargs: object) -> dict[str, object]:
        return {
            "pk": _string_attr(f"SOURCE#{kwargs['app_id']}"),
            "sk": _string_attr(f"REV#{kwargs['revision']}"),
        }

    def _transact_put_new(self, items: list[dict[str, object]]) -> None:
        app_meta, group_index, _manifest = items
        app_id = _item_string(app_meta, "app_id")
        if app_id in self._app_meta:
            raise AssertionError("duplicate app id")
        self._app_meta[app_id] = app_meta
        self._group_items.append(group_index)

    def _delete_failed_write(self, *args: object) -> None:
        raise AssertionError("cleanup should not run")

    def _public_hosted_app(self, item: dict[str, object]) -> dict[str, object]:
        result: dict[str, object] = {
            "app_id": _item_string(item, "app_id"),
            "group_id": _item_string(item, "group_id"),
            "title": _item_string(item, "title"),
            "owner_user_id": _item_string(item, "owner_user_id"),
            "source_kind": _item_string(item, "source_kind"),
            "created_at": _item_string(item, "created_at"),
            "source_revision": int(item["source_revision"]["N"]),
            "source_sha256": _item_string(item, "source_sha256"),
            "editable": item["editable"]["BOOL"],
        }
        package = item.get("package_id")
        if isinstance(package, dict) and isinstance(package.get("S"), str):
            result["package_id"] = package["S"]
        return result

    def update_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
        zip_bytes: bytes,
    ) -> dict[str, object]:
        if auth_subject != "subject" or group_id != GROUP_ID:
            raise AssertionError((auth_subject, group_id))
        group_item = self._require_app_in_group(app_id, group_id)
        current_revision = int(group_item["source_revision"]["N"])
        if current_revision != expected_revision:
            raise AssertionError((current_revision, expected_revision))
        next_revision = current_revision + 1
        sha256 = hashlib.sha256(zip_bytes).hexdigest()
        for item in (group_item, self._app_meta[app_id]):
            item["source_revision"] = _number_attr(next_revision)
            item["source_sha256"] = _string_attr(sha256)
        self.update_calls.append((app_id, expected_revision))
        return {
            "app_id": app_id,
            "group_id": group_id,
            "revision": next_revision,
            "sha256": sha256,
            "files": ["index.html"],
            "updated_at": "2026-09-17T00:00:00Z",
        }

    def add_legacy_duplicate(self, source: dict[str, object]) -> None:
        duplicate = deepcopy(source)
        app_id = "f" * 32
        duplicate["app_id"] = _string_attr(app_id)
        duplicate["pk"] = _string_attr(f"GROUP#{GROUP_ID}")
        duplicate["sk"] = _string_attr(f"APP#{app_id}")
        duplicate.pop("package_id", None)
        self._group_items.append(duplicate)
        meta = deepcopy(duplicate)
        meta["pk"] = _string_attr(f"APP#{app_id}")
        meta["sk"] = _string_attr("META")
        self._app_meta[app_id] = meta


class HostedUploadIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeUploadBackend()

    def upload(self, title: str, data: bytes) -> dict[str, object]:
        return create_uploaded_app(
            self.backend,
            "subject",
            GROUP_ID,
            title,
            data,
        )

    def test_same_package_identity_updates_existing_app(self) -> None:
        first = self.upload("うさぎのおやつやさん", make_zip("<h1>v1</h1>", PACKAGE_A))
        second = self.upload("うさぎのおやつやさん", make_zip("<h1>v2</h1>", PACKAGE_A))

        self.assertEqual(second["app_id"], first["app_id"])
        self.assertEqual(second["source_revision"], 2)
        self.assertEqual(len(self.backend._group_items), 1)
        self.assertEqual(self.backend.update_calls, [(first["app_id"], 1)])

    def test_different_package_identity_creates_new_app(self) -> None:
        first = self.upload("ゲームA", make_zip("<h1>A</h1>", PACKAGE_A))
        second = self.upload("ゲームB", make_zip("<h1>B</h1>", PACKAGE_B))

        self.assertNotEqual(second["app_id"], first["app_id"])
        self.assertEqual(len(self.backend._group_items), 2)

    def test_identical_zip_is_idempotent(self) -> None:
        data = make_zip("<h1>same</h1>", PACKAGE_A)
        first = self.upload("同じゲーム", data)
        second = self.upload("同じゲーム", data)

        self.assertEqual(second["app_id"], first["app_id"])
        self.assertEqual(second["source_revision"], 1)
        self.assertEqual(self.backend.update_calls, [])
        self.assertEqual(len(self.backend._group_items), 1)

    def test_legacy_same_title_updates_when_unambiguous(self) -> None:
        first = self.upload("昔のゲーム", make_zip("<h1>v1</h1>"))
        second = self.upload("昔のゲーム", make_zip("<h1>v2</h1>"))

        self.assertEqual(second["app_id"], first["app_id"])
        self.assertEqual(second["source_revision"], 2)
        self.assertEqual(len(self.backend._group_items), 1)

    def test_duplicate_legacy_title_fails_instead_of_guessing(self) -> None:
        self.upload("重複ゲーム", make_zip("<h1>v1</h1>"))
        self.backend.add_legacy_duplicate(self.backend._group_items[0])

        with self.assertRaises(ApiProblem) as caught:
            self.upload("重複ゲーム", make_zip("<h1>v2</h1>"))

        self.assertEqual(caught.exception.error, "ambiguous_legacy_upload")

    def test_missing_manifest_does_not_overwrite_packaged_app(self) -> None:
        self.upload("新しいゲーム", make_zip("<h1>v1</h1>", PACKAGE_A))

        with self.assertRaises(ApiProblem) as caught:
            self.upload("新しいゲーム", make_zip("<h1>v2</h1>"))

        self.assertEqual(caught.exception.error, "missing_package_identity")

    def test_package_identity_requires_same_title(self) -> None:
        self.upload("元の名前", make_zip("<h1>v1</h1>", PACKAGE_A))

        with self.assertRaises(ApiProblem) as caught:
            self.upload("別の名前", make_zip("<h1>v2</h1>", PACKAGE_A))

        self.assertEqual(caught.exception.error, "package_title_mismatch")


if __name__ == "__main__":
    unittest.main()
