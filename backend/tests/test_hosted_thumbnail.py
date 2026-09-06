from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_catalog_backend import HostedCatalogBackend  # noqa: E402
from hosted_thumbnail import (  # noqa: E402
    MAX_THUMBNAIL_BYTES,
    get_thumbnail,
    set_thumbnail,
)
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402
from test_hosted_catalog_backend import FakeS3, source_zip  # noqa: E402


class HostedThumbnailTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.metadata = FakeDynamoDb()
        self.runtime = FakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[("uploads", "hosted/templates/shiba-game/v1/source.zip")] = source_zip(
            "<h1>game-v1</h1>"
        )
        self.backend = HostedCatalogBackend(
            cognito=self.cognito,
            dynamodb=self.metadata,
            runtime_dynamodb=self.runtime,
            s3=self.s3,
            user_pool_id="pool",
            app_client_id="client",
            table_name="metadata",
            runtime_table_name="runtime",
            upload_bucket="uploads",
            published_bucket="published",
        )
        self.alice = self._register("alice")
        group = self.backend.create_group(self.alice, "サムネ部屋")
        installed = self.backend.install_builtin(
            self.alice,
            group["group_id"],
            "shiba-game",
        )
        self.app = self.backend.fork_app(
            self.alice,
            group["group_id"],
            installed["app_id"],
            "サムネアプリ",
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(login_id, "secret12")
        return self.cognito.users[login_id]["sub"]

    def test_owner_can_save_and_read_thumbnail(self) -> None:
        with self.assertRaises(ApiProblem) as missing:
            get_thumbnail(self.backend, self.alice, self.app["app_id"])
        self.assertEqual(missing.exception.status_code, 404)
        self.assertEqual(missing.exception.error, "thumbnail_not_found")

        data = b"\x89PNG\r\n\x1a\nthumbnail"
        saved = set_thumbnail(
            self.backend,
            self.alice,
            self.app["app_id"],
            data=data,
            content_type="image/png",
        )
        self.assertEqual(saved["app_id"], self.app["app_id"])
        self.assertEqual(saved["content_type"], "image/png")
        self.assertEqual(saved["bytes"], len(data))

        stored, content_type = get_thumbnail(
            self.backend,
            self.alice,
            self.app["app_id"],
        )
        self.assertEqual(stored, data)
        self.assertEqual(content_type, "image/png")

        item = self.metadata.items[(f"APP#{self.app['app_id']}", "META")]
        self.assertEqual(item["thumbnail_bytes"], {"B": data})
        self.assertEqual(item["thumbnail_content_type"], {"S": "image/png"})
        self.assertIn("thumbnail_updated_at", item)

    def test_thumbnail_validation_is_fail_closed(self) -> None:
        with self.assertRaises(ApiProblem) as bad_type:
            set_thumbnail(
                self.backend,
                self.alice,
                self.app["app_id"],
                data=b"GIF89a",
                content_type="image/gif",
            )
        self.assertEqual(bad_type.exception.status_code, 415)

        with self.assertRaises(ApiProblem) as bad_signature:
            set_thumbnail(
                self.backend,
                self.alice,
                self.app["app_id"],
                data=b"not-a-png",
                content_type="image/png",
            )
        self.assertEqual(bad_signature.exception.error, "invalid_thumbnail")

        with self.assertRaises(ApiProblem) as too_large:
            set_thumbnail(
                self.backend,
                self.alice,
                self.app["app_id"],
                data=b"\xff\xd8\xff" + b"x" * MAX_THUMBNAIL_BYTES,
                content_type="image/jpeg",
            )
        self.assertEqual(too_large.exception.status_code, 413)

    def test_non_owner_cannot_read_or_replace_thumbnail(self) -> None:
        bob = self._register("bob")
        data = b"RIFF\x00\x00\x00\x00WEBPthumbnail"
        set_thumbnail(
            self.backend,
            self.alice,
            self.app["app_id"],
            data=data,
            content_type="image/webp",
        )

        for operation in (
            lambda: get_thumbnail(self.backend, bob, self.app["app_id"]),
            lambda: set_thumbnail(
                self.backend,
                bob,
                self.app["app_id"],
                data=data,
                content_type="image/webp",
            ),
        ):
            with self.assertRaises(ApiProblem) as denied:
                operation()
            self.assertEqual(denied.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
