from __future__ import annotations

import hashlib
import json
import uuid
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from phase2_backend import _now_iso, _optional_item_string, _safe_zip_paths
from phase3_backend import Phase3AwsBackend


class Phase4AwsBackend(Phase3AwsBackend):
    """Versioning and soft-delete rules on top of the Phase 2/3 model."""

    def _app_meta_item(self, app_id: str) -> dict[str, Any]:
        item = self._get_item(pk=f"APP#{app_id}", sk="META")
        if item is None:
            raise ApiProblem(404, "app_not_found", "指定された作品が見つかりません。")
        return item

    @staticmethod
    def _app_status(item: dict[str, Any]) -> str:
        raw = item.get("status")
        if raw is None:
            return "active"
        status = _item_string(item, "status")
        if status not in {"active", "archived"}:
            raise RuntimeError(f"Unsupported stored app status: {status!r}")
        return status

    def _require_active_app(self, app_id: str) -> dict[str, Any]:
        meta = self._app_meta_item(app_id)
        if self._app_status(meta) != "active":
            raise ApiProblem(409, "app_archived", "この作品は削除済みです。")
        return meta

    def _version_items(self, app_id: str) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"APP#{app_id}"),
                ":prefix": _string_attr("VERSION#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    @staticmethod
    def _latest_approved(items: list[dict[str, Any]]) -> dict[str, Any] | None:
        approved = [item for item in items if _item_string(item, "status") == "approved"]
        if not approved:
            return None
        return max(
            approved,
            key=lambda item: (
                _item_string(item, "reviewed_at"),
                _item_string(item, "created_at"),
                _item_string(item, "version_id"),
            ),
        )

    def upload_app_version(
        self,
        auth_subject: str,
        app_id: str,
        filename: str,
        zip_bytes: bytes,
    ) -> dict[str, Any]:
        student = self._user_by_auth_subject(auth_subject)
        self._require_role(student, "student")
        meta = self._require_active_app(app_id)
        if _item_string(meta, "owner_user_id") != student.user_id:
            raise ApiProblem(403, "forbidden", "この作品を更新する権限がありません。")

        group_id = _item_string(meta, "group_id")
        group_name = self._require_active_membership(student.user_id, group_id, "student")
        existing = self._version_items(app_id)
        if any(_item_string(item, "status") in {"draft", "pending_review"} for item in existing):
            raise ApiProblem(
                409,
                "unfinished_version_exists",
                "下書きまたは確認待ちの更新版があります。先にその版を公開申請・確認してください。",
            )

        files = _safe_zip_paths(zip_bytes)
        version_id = uuid.uuid4().hex
        created_at = _now_iso()
        digest = hashlib.sha256(zip_bytes).hexdigest()
        source_key = f"drafts/{group_id}/{student.user_id}/{app_id}/{version_id}/source.zip"
        try:
            self._s3.put_object(
                Bucket=self._upload_bucket,
                Key=source_key,
                Body=zip_bytes,
                ContentType="application/zip",
                Metadata={"sha256": digest},
                IfNoneMatch="*",
            )
        except Exception as exc:
            code = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if code in {"PreconditionFailed", "ConditionalRequestConflict"}:
                raise RuntimeError("Generated S3 object key unexpectedly already exists") from exc
            raise

        common = {
            "entity": _string_attr("app_version"),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(group_id),
            "group_name": _string_attr(group_name),
            "owner_user_id": _string_attr(student.user_id),
            "owner_login_id": _string_attr(student.login_id),
            "title": _string_attr(_item_string(meta, "title")),
            "filename": _string_attr(filename),
            "status": _string_attr("draft"),
            "source_key": _string_attr(source_key),
            "sha256": _string_attr(digest),
            "files_json": _string_attr(json.dumps(files, ensure_ascii=False, separators=(",", ":"))),
            "created_at": _string_attr(created_at),
        }
        description = _optional_item_string(meta, "description")
        if description is not None:
            common["description"] = _string_attr(description)

        version = {"pk": _string_attr(f"APP#{app_id}"), "sk": _string_attr(f"VERSION#{version_id}"), **common}
        group_index = {"pk": _string_attr(f"GROUP#{group_id}"), "sk": _string_attr(f"APP#{app_id}#VERSION#{version_id}"), **common}
        user_index = {"pk": _string_attr(f"USER#{student.user_id}"), "sk": _string_attr(f"APP#{app_id}#VERSION#{version_id}"), **common}
        try:
            self._transact_put_new([version, group_index, user_index])
        except Exception:
            try:
                self._s3.delete_object(Bucket=self._upload_bucket, Key=source_key)
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Version metadata creation failed after S3 upload, and S3 cleanup also failed."
                ) from cleanup_exc
            raise

        payload = self._public_version(version)
        payload.update({
            "version_number": len(existing) + 1,
            "version_count": len(existing) + 1,
            "is_latest_version": True,
            "is_published": False,
            "app_status": "active",
        })
        return payload

    def list_my_apps_lifecycle(self, auth_subject: str) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"USER#{user.user_id}"),
                ":prefix": _string_attr("APP#"),
            },
            ConsistentRead=True,
        )
        by_app: dict[str, list[dict[str, Any]]] = {}
        for version in self._query_items(response):
            by_app.setdefault(_item_string(version, "app_id"), []).append(version)

        result: list[dict[str, Any]] = []
        for app_id, app_versions in by_app.items():
            meta = self._app_meta_item(app_id)
            status = self._app_status(meta)
            if status == "archived":
                continue
            ordered = sorted(
                app_versions,
                key=lambda item: (_item_string(item, "created_at"), _item_string(item, "version_id")),
            )
            published = self._latest_approved(ordered)
            published_id = None if published is None else _item_string(published, "version_id")
            for index, item in enumerate(ordered, start=1):
                payload = self._public_version(item)
                payload.update({
                    "version_number": index,
                    "version_count": len(ordered),
                    "is_latest_version": index == len(ordered),
                    "is_published": _item_string(item, "version_id") == published_id,
                    "app_status": status,
                })
                result.append(payload)
        result.sort(
            key=lambda item: (item["created_at"], item["app_id"], item["version_number"]),
            reverse=True,
        )
        return result

    def archive_app(self, auth_subject: str, app_id: str) -> None:
        student = self._user_by_auth_subject(auth_subject)
        self._require_role(student, "student")
        meta = self._require_active_app(app_id)
        if _item_string(meta, "owner_user_id") != student.user_id:
            raise ApiProblem(403, "forbidden", "この作品を削除する権限がありません。")
        group_id = _item_string(meta, "group_id")
        self._require_active_membership(student.user_id, group_id, "student")
        versions = self._version_items(app_id)
        if any(_item_string(item, "status") == "pending_review" for item in versions):
            raise ApiProblem(
                409,
                "review_in_progress",
                "先生の確認待ちの版があるため削除できません。確認が終わってから削除してください。",
            )
        self._dynamodb.update_item(
            TableName=self._table_name,
            Key={"pk": _string_attr(f"APP#{app_id}"), "sk": _string_attr("META")},
            UpdateExpression="SET #status = :archived, archived_at = :archived_at",
            ConditionExpression="owner_user_id = :owner AND (attribute_not_exists(#status) OR #status = :active)",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":owner": _string_attr(student.user_id),
                ":active": _string_attr("active"),
                ":archived": _string_attr("archived"),
                ":archived_at": _string_attr(_now_iso()),
            },
        )

    def approve_app(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self._require_active_app(app_id)
        return super().approve_app(auth_subject, app_id, version_id)

    def list_mobile_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        candidates = super().list_mobile_apps(auth_subject)
        by_app: dict[str, dict[str, Any]] = {}
        for candidate in candidates:
            app_id = candidate["app_id"]
            if not isinstance(app_id, str):
                raise RuntimeError("Mobile catalogue app_id is not a string")
            if self._app_status(self._app_meta_item(app_id)) == "archived":
                continue
            previous = by_app.get(app_id)
            if previous is None or (
                candidate["reviewed_at"], candidate["created_at"], candidate["version_id"]
            ) > (
                previous["reviewed_at"], previous["created_at"], previous["version_id"]
            ):
                by_app[app_id] = candidate
        apps = list(by_app.values())
        apps.sort(key=lambda item: (item["reviewed_at"], item["created_at"], item["app_id"]), reverse=True)
        return apps

    def create_launch(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        self._require_active_app(app_id)
        latest = self._latest_approved(self._version_items(app_id))
        if latest is None or _item_string(latest, "version_id") != version_id:
            raise ApiProblem(409, "old_version_not_published", "この作品には新しい公開版があります。一覧を更新してください。")
        return super().create_launch(auth_subject, app_id, version_id)
