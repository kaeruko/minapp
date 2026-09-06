from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import unittest
from types import SimpleNamespace
from typing import Any
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from aws_backend import _item_string, _string_attr  # noqa: E402
from errors import ApiProblem  # noqa: E402
import hosted_authoring_session  # noqa: E402
from hosted_platform_backend import _number_attr  # noqa: E402
from test_hosted_backend import FakeAwsError  # noqa: E402


class SessionDynamo:
    def __init__(self, items: dict[tuple[str, str], dict[str, Any]]) -> None:
        self.items = items

    @staticmethod
    def _s(attribute: dict[str, str]) -> str:
        return attribute["S"]

    def update_item(self, **request: Any) -> dict[str, Any]:
        key = (
            self._s(request["Key"]["pk"]),
            self._s(request["Key"]["sk"]),
        )
        item = self.items.get(key)
        if item is None:
            raise FakeAwsError("ConditionalCheckFailedException")
        values = request["ExpressionAttributeValues"]
        current = int(item["request_count"]["N"])
        limit = int(values[":limit"]["N"])
        now = int(values[":now"]["N"])
        expires = int(item["expires_at_epoch"]["N"])
        if current >= limit or expires <= now:
            raise FakeAwsError("ConditionalCheckFailedException")
        replacement = dict(item)
        replacement["request_count"] = _number_attr(current + 1)
        self.items[key] = replacement
        return {}


class FakeBackend:
    def __init__(self) -> None:
        self._table_name = "metadata"
        self.items: dict[tuple[str, str], dict[str, Any]] = {}
        self._dynamodb = SessionDynamo(self.items)
        self.user = SimpleNamespace(user_id="1" * 32)
        self.auth_subject = "sub-owner"
        self.content_id = "3" * 32
        self.group_id = "2" * 32
        self.editor_app_id = "4" * 32
        self.content = {
            "content_id": _string_attr(self.content_id),
            "group_id": _string_attr(self.group_id),
            "owner_user_id": _string_attr(self.user.user_id),
            "content_format": _string_attr("minapp/novel@1"),
            "status": _string_attr("draft"),
        }
        self.editor = {
            "app_id": _string_attr(self.editor_app_id),
            "group_id": _string_attr(self.group_id),
            "edits_json": _string_attr('["minapp/novel@1"]'),
        }
        self.calls: list[tuple[Any, ...]] = []

    def _owned_content(self, auth_subject: str, content_id: str) -> tuple[Any, dict[str, Any]]:
        if auth_subject != self.auth_subject or content_id != self.content_id:
            raise ApiProblem(404, "content_not_found", "not found")
        return self.user, self.content

    def _require_app_in_group(self, app_id: str, group_id: str) -> dict[str, Any]:
        if app_id != self.editor_app_id or group_id != self.group_id:
            raise ApiProblem(404, "app_not_found", "not found")
        return self.editor

    @staticmethod
    def _require_not_deleting(app: dict[str, Any]) -> None:
        if "deletion_state" in app:
            raise ApiProblem(409, "app_deleting", "deleting")

    def _transact_put_new(self, items: list[dict[str, Any]]) -> None:
        for item in items:
            key = (_item_string(item, "pk"), _item_string(item, "sk"))
            if key in self.items:
                raise AssertionError("duplicate session item")
        for item in items:
            self.items[(_item_string(item, "pk"), _item_string(item, "sk"))] = item

    def _get_item(self, *, pk: str, sk: str) -> dict[str, Any] | None:
        return self.items.get((pk, sk))

    def load_authoring_project(self, auth_subject: str, content_id: str) -> dict[str, Any]:
        self.calls.append(("load", auth_subject, content_id))
        return {"content_id": content_id, "draft_revision": 1, "document": {"version": 1}}

    def save_authoring_document(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        self.calls.append(("save-document", auth_subject, content_id, expected_revision, document))
        return {"content_id": content_id, "draft_revision": expected_revision + 1}

    def get_authoring_asset(self, auth_subject: str, content_id: str, path: str) -> tuple[bytes, str]:
        self.calls.append(("get-asset", auth_subject, content_id, path))
        return b"OggS", "audio/ogg"

    def save_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
        data: bytes,
    ) -> dict[str, Any]:
        self.calls.append(("save-asset", auth_subject, content_id, expected_revision, path, data))
        return {"content_id": content_id, "draft_revision": expected_revision + 1}

    def delete_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
    ) -> dict[str, Any]:
        self.calls.append(("delete-asset", auth_subject, content_id, expected_revision, path))
        return {"content_id": content_id, "draft_revision": expected_revision + 1}


class HostedAuthoringSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()

    def _session(self) -> dict[str, Any]:
        return hosted_authoring_session.create_session(
            self.backend,
            self.backend.auth_subject,
            self.backend.content_id,
            self.backend.editor_app_id,
        )

    def test_session_binds_editor_content_user_and_never_stores_raw_token_as_key(self) -> None:
        session = self._session()
        token = session["token"]
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        item = self.backend.items[(f"AUTHORINGSESSION#{token_hash}", "META")]

        self.assertEqual(_item_string(item, "content_id"), self.backend.content_id)
        self.assertEqual(_item_string(item, "editor_app_id"), self.backend.editor_app_id)
        self.assertEqual(_item_string(item, "user_id"), self.backend.user.user_id)
        self.assertEqual(_item_string(item, "content_format"), "minapp/novel@1")
        self.assertNotIn((f"AUTHORINGSESSION#{token}", "META"), self.backend.items)
        self.assertEqual(
            session["allowed_operations"],
            ["load", "save_document", "get_asset", "save_asset", "delete_asset"],
        )

    def test_capability_operations_use_only_bound_content_and_subject(self) -> None:
        token = self._session()["token"]
        loaded = hosted_authoring_session.load_project(self.backend, token)
        saved = hosted_authoring_session.save_document(
            self.backend,
            token,
            expected_revision=1,
            document={"version": 1, "start": "end"},
        )

        self.assertEqual(loaded["content_id"], self.backend.content_id)
        self.assertEqual(saved["draft_revision"], 2)
        self.assertEqual(
            self.backend.calls,
            [
                ("load", self.backend.auth_subject, self.backend.content_id),
                (
                    "save-document",
                    self.backend.auth_subject,
                    self.backend.content_id,
                    1,
                    {"version": 1, "start": "end"},
                ),
            ],
        )

    def test_editor_must_explicitly_declare_exact_content_format(self) -> None:
        self.backend.editor["edits_json"] = _string_attr('["minapp/quiz@1"]')
        with self.assertRaises(ApiProblem) as caught:
            self._session()
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "editor_content_format_mismatch")
        self.assertFalse(self.backend.items)

    def test_missing_editor_contract_is_not_treated_as_wildcard(self) -> None:
        self.backend.editor.pop("edits_json")
        with self.assertRaises(ApiProblem) as caught:
            self._session()
        self.assertEqual(caught.exception.error, "editor_not_authoring_capable")
        self.assertFalse(self.backend.items)

    def test_expired_session_stops_before_backend_operation(self) -> None:
        token = self._session()["token"]
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        item = self.backend.items[(f"AUTHORINGSESSION#{token_hash}", "META")]
        item["expires_at_epoch"] = _number_attr(10)
        with patch.object(hosted_authoring_session.time, "time", return_value=10):
            with self.assertRaises(ApiProblem) as caught:
                hosted_authoring_session.load_project(self.backend, token)
        self.assertEqual(caught.exception.error, "authoring_session_not_found")
        self.assertEqual(self.backend.calls, [])

    def test_request_budget_is_atomic_and_fail_closed(self) -> None:
        token = self._session()["token"]
        with patch.object(hosted_authoring_session, "MAX_AUTHORING_REQUESTS_PER_SESSION", 1):
            hosted_authoring_session.load_project(self.backend, token)
            with self.assertRaises(ApiProblem) as caught:
                hosted_authoring_session.load_project(self.backend, token)
        self.assertEqual(caught.exception.status_code, 429)
        self.assertEqual(caught.exception.error, "authoring_request_limit_reached")
        self.assertEqual(self.backend.calls, [("load", self.backend.auth_subject, self.backend.content_id)])


if __name__ == "__main__":
    unittest.main()
