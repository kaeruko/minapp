from __future__ import annotations

import hashlib
import io
import secrets
import time
import zipfile
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from phase2_backend import (
    MAX_FILE_BYTES,
    MAX_ZIP_BYTES,
    Phase2AwsBackend,
    _content_type,
    _item_number,
    _now_iso,
    _number_attr,
    _safe_zip_paths,
)

LAUNCH_TTL_SECONDS = 10 * 60
REPORT_REASONS = frozenset(
    {
        "不適切な表現・内容",
        "嫌がらせ・いじめ",
        "個人情報が含まれている",
        "危険な内容",
        "その他",
    }
)


class Phase3AwsBackend(Phase2AwsBackend):
    def list_mobile_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        memberships = self._membership_items_for_user(user.user_id)

        apps: list[dict[str, Any]] = []
        for membership in memberships:
            if _item_string(membership, "status") != "active":
                continue
            role = _item_string(membership, "role")
            if role not in {"student", "teacher"}:
                raise RuntimeError(f"Unsupported stored membership role: {role!r}")

            group_id = _item_string(membership, "group_id")
            response = self._dynamodb.query(
                TableName=self._table_name,
                KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
                ExpressionAttributeValues={
                    ":pk": _string_attr(f"GROUP#{group_id}"),
                    ":prefix": _string_attr("APP#"),
                },
                ConsistentRead=True,
            )
            for item in self._query_items(response):
                if _item_string(item, "status") != "approved":
                    continue
                # An approved version without a published object is inconsistent state.
                _item_string(item, "published_key")
                apps.append(self._mobile_public_version(item))

        apps.sort(
            key=lambda item: item.get("reviewed_at", item["created_at"]),
            reverse=True,
        )
        return apps

    def create_launch(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        if _item_string(version, "status") != "approved":
            raise ApiProblem(409, "app_not_published", "承認済みの作品だけ起動できます。")

        group_id = _item_string(version, "group_id")
        self._require_active_membership(user.user_id, group_id, user.role)

        token = secrets.token_urlsafe(32)
        expires_at = int(time.time()) + LAUNCH_TTL_SECONDS
        item = {
            "pk": _string_attr(f"LAUNCH#{token}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("launch_token"),
            "published_key": _string_attr(_item_string(version, "published_key")),
            "sha256": _string_attr(_item_string(version, "sha256")),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(group_id),
            "issued_to_user_id": _string_attr(user.user_id),
            "expires_at": _number_attr(expires_at),
        }
        self._transact_put_new([item])
        return {
            "content_path": f"/launch/{token}/index.html",
            "expires_in": LAUNCH_TTL_SECONDS,
        }

    def create_report(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
        reason: str,
    ) -> dict[str, Any]:
        if reason not in REPORT_REASONS:
            raise ApiProblem(400, "invalid_report_reason", "報告理由が不正です。")

        reporter = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        if _item_string(version, "status") != "approved":
            raise ApiProblem(409, "app_not_published", "公開中の作品だけ報告できます。")

        group_id = _item_string(version, "group_id")
        self._require_active_membership(reporter.user_id, group_id, reporter.role)
        owner_user_id = _item_string(version, "owner_user_id")
        report_id = secrets.token_hex(16)
        created_at = _now_iso()
        item = {
            "pk": _string_attr(f"REPORT#{report_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("ugc_report"),
            "report_id": _string_attr(report_id),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(group_id),
            "reported_owner_user_id": _string_attr(owner_user_id),
            "reported_by_user_id": _string_attr(reporter.user_id),
            "reason": _string_attr(reason),
            "status": _string_attr("open"),
            "created_at": _string_attr(created_at),
        }
        self._transact_put_new([item])
        return {
            "report_id": report_id,
            "status": "received",
            "created_at": created_at,
        }

    def get_launch_file(self, token: str, path: str) -> tuple[bytes, str]:
        item = self._get_item(pk=f"LAUNCH#{token}", sk="META")
        if item is None:
            raise ApiProblem(404, "launch_not_found", "起動URLが無効です。")
        if _item_number(item, "expires_at") < int(time.time()):
            raise ApiProblem(404, "launch_expired", "起動URLの有効期限が切れました。")

        normalized = self._normalize_content_path(path)
        published_key = _item_string(item, "published_key")
        response = self._s3.get_object(
            Bucket=self._published_bucket,
            Key=published_key,
        )
        body = response.get("Body")
        if body is None or not hasattr(body, "read"):
            raise RuntimeError("S3 GetObject response has no readable Body")
        zip_bytes = body.read(MAX_ZIP_BYTES + 1)
        if not isinstance(zip_bytes, bytes):
            raise RuntimeError("S3 Body.read() did not return bytes")
        if len(zip_bytes) > MAX_ZIP_BYTES:
            raise RuntimeError("Stored published ZIP exceeds configured maximum size")
        if hashlib.sha256(zip_bytes).hexdigest() != _item_string(item, "sha256"):
            raise RuntimeError("Stored published ZIP hash does not match app metadata")

        try:
            with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
                names = set(_safe_zip_paths(zip_bytes))
                if normalized not in names:
                    raise ApiProblem(404, "launch_file_not_found", "作品内のファイルが見つかりません。")
                data = archive.read(normalized)
        except zipfile.BadZipFile as exc:
            raise RuntimeError("Stored published app ZIP became unreadable") from exc

        if len(data) > MAX_FILE_BYTES:
            raise RuntimeError("Stored launch file exceeds configured maximum size")
        return data, _content_type(normalized)

    @staticmethod
    def _mobile_public_version(item: dict[str, Any]) -> dict[str, Any]:
        payload = Phase2AwsBackend._public_version(item)
        reviewed_at = payload.get("reviewed_at")
        if not isinstance(reviewed_at, str) or not reviewed_at:
            raise RuntimeError("Approved app version has no reviewed_at timestamp")
        return payload
