from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_legal import PRIVACY_VERSION, TERMS_VERSION  # noqa: E402
from hosted_legal_backend import HostedLegalBackend  # noqa: E402
from test_hosted_backend import FakeCognito, FakeDynamoDb  # noqa: E402
from test_hosted_catalog_backend import FakeS3, source_zip  # noqa: E402


class HostedLegalDeletionRetryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cognito = FakeCognito()
        self.dynamo = FakeDynamoDb()
        self.s3 = FakeS3()
        self.s3.objects[
            ("uploads", "hosted/templates/novel-starter/v4/source.zip")
        ] = source_zip("<!doctype html><h1>novel-v4</h1>")
        self.backend = HostedLegalBackend(
            cognito=self.cognito,
            dynamodb=self.dynamo,
            runtime_dynamodb=self.dynamo,
            s3=self.s3,
            user_pool_id="pool",
            app_client_id="client",
            table_name="table",
            runtime_table_name="runtime-table",
            upload_bucket="uploads",
            published_bucket="published",
        )

    def _register(self, login_id: str) -> str:
        self.backend.register(
            login_id,
            "secret12",
            TERMS_VERSION,
            PRIVACY_VERSION,
        )
        return self.cognito.users[login_id]["sub"]

    def test_owned_app_deletion_can_resume_after_s3_cleanup_failure(self) -> None:
        subject = self._register("retry-owner")
        group = self.backend.create_group(subject, "再試行部")
        installed = self.backend.install_builtin(
            subject,
            group["group_id"],
            "novel-starter",
        )
        forked = self.backend.fork_app(
            subject,
            group["group_id"],
            installed["app_id"],
            "再試行する作品",
        )
        app_id = forked["app_id"]

        original_delete = self.s3.delete_object
        failed = False

        def fail_first_delete(**request: Any) -> dict[str, Any]:
            nonlocal failed
            if not failed:
                failed = True
                raise RuntimeError("simulated S3 cleanup failure")
            return original_delete(**request)

        self.s3.delete_object = fail_first_delete  # type: ignore[method-assign]
        with self.assertRaisesRegex(RuntimeError, "simulated S3 cleanup failure"):
            self.backend.delete_hosted_app(subject, group["group_id"], app_id)

        app_item = self.dynamo.items[(f"APP#{app_id}", "META")]
        self.assertEqual(app_item["deletion_state"]["S"], "deleting")

        self.s3.delete_object = original_delete  # type: ignore[method-assign]
        self.backend.delete_hosted_app(subject, group["group_id"], app_id)

        self.assertNotIn((f"APP#{app_id}", "META"), self.dynamo.items)
        self.assertNotIn(
            (f"GROUP#{group['group_id']}", f"APP#{app_id}"),
            self.dynamo.items,
        )


if __name__ == "__main__":
    unittest.main()
