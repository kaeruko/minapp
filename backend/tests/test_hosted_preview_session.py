from __future__ import annotations

import hashlib
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

import hosted_preview_session  # noqa: E402
from aws_backend import _item_string  # noqa: E402


class HarnessBackend:
    def __init__(self) -> None:
        self.transactions: list[list[dict[str, Any]]] = []

    def _source_revision(self, app: dict[str, Any]) -> int:
        return 7

    def _read_current_source(
        self, app: dict[str, Any]
    ) -> tuple[bytes, list[str], str]:
        return b"zip", ["index.html", "audio/bgm.ogg"], "a" * 64

    def _transact_put_new(self, items: list[dict[str, Any]]) -> None:
        self.transactions.append(items)


class HostedPreviewSessionTests(unittest.TestCase):
    def test_content_and_preview_runtime_capabilities_are_created_atomically(self) -> None:
        backend = HarnessBackend()
        app = {
            "group_id": {"S": "2" * 32},
            "source_key": {"S": "draft/source.zip"},
        }
        user = SimpleNamespace(user_id="1" * 32)

        with patch.object(
            hosted_preview_session,
            "_owned_editable_app",
            return_value=(user, app),
        ):
            result = hosted_preview_session.create_preview_session(
                backend,
                "sub-owner",
                "3" * 32,
            )

        self.assertEqual(len(backend.transactions), 1)
        self.assertEqual(len(backend.transactions[0]), 2)
        content_session, runtime_session = backend.transactions[0]

        content_token = result["content_path"].split("/")[3]
        runtime_token = result["runtime_token"]
        self.assertEqual(
            _item_string(content_session, "pk"),
            "HOSTEDPREVIEW#" + hashlib.sha256(content_token.encode("ascii")).hexdigest(),
        )
        self.assertEqual(
            _item_string(runtime_session, "pk"),
            "RUNTIMESESSION#" + hashlib.sha256(runtime_token.encode("ascii")).hexdigest(),
        )
        self.assertEqual(_item_string(runtime_session, "group_id"), "2" * 32)
        self.assertEqual(_item_string(runtime_session, "app_id"), "3" * 32)
        self.assertEqual(_item_string(runtime_session, "user_id"), "1" * 32)
        preview_state_id = _item_string(runtime_session, "preview_state_id")
        self.assertEqual(len(preview_state_id), 64)
        self.assertTrue(all(character in "0123456789abcdef" for character in preview_state_id))
        self.assertEqual(result["expires_in"], 600)
        self.assertEqual(result["runtime_expires_in"], 600)


if __name__ == "__main__":
    unittest.main()
