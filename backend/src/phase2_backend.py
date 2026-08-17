from __future__ import annotations

import hashlib
import io
import json
import mimetypes
import secrets
import stat
import time
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import PurePosixPath
from typing import Any

from aws_backend import AwsBackend, _item_string, _required_env, _string_attr
from errors import ApiProblem

MAX_ZIP_BYTES = 2 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_FILE_COUNT = 100
PREVIEW_TTL_SECONDS = 15 * 60

_ALLOWED_SUFFIXES = {
    ".html",
    ".css",
    ".js",
    ".mjs",
    ".json",
    ".txt",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".ico",
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _number_attr(value: int) -> dict[str, str]:
    if not isinstance(value, int):
        raise TypeError("DynamoDB number must be an integer")
    return {"N": str(value)}


def _item_number(item: dict[str, Any], key: str) -> int:
    raw = item.get(key)
    if not isinstance(raw, dict):
        raise RuntimeError(f"DynamoDB item is missing number attribute {key!r}")
    value = raw.get("N")
    if not isinstance(value, str):
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a number")
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not an integer") from exc


def _safe_zip_paths(data: bytes) -> list[str]:
    if not isinstance(data, bytes):
        raise TypeError("ZIP payload must be bytes")
    if not data:
        raise ApiProblem(400, "empty_zip", "ZIPファイルが空です。")
    if len(data) > MAX_ZIP_BYTES:
        raise ApiProblem(413, "zip_too_large", "ZIPファイルは2MB以下にしてください。")

    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise ApiProblem(400, "invalid_zip", "正しいZIPファイルではありません。") from exc

    files: list[str] = []
    seen: set[str] = set()
    total_uncompressed = 0

    with archive:
        for info in archive.infolist():
            raw_name = info.filename
            if not isinstance(raw_name, str) or not raw_name:
                raise ApiProblem(400, "invalid_zip_path", "ZIP内に不正なファイル名があります。")
            if "\\" in raw_name or "\x00" in raw_name or raw_name.startswith("/"):
                raise ApiProblem(400, "invalid_zip_path", f"ZIP内のパスが不正です: {raw_name}")

            parts = raw_name.rstrip("/").split("/")
            if any(part in {"", ".", ".."} for part in parts):
                raise ApiProblem(400, "invalid_zip_path", f"ZIP内のパスが不正です: {raw_name}")

            mode = (info.external_attr >> 16) & 0o170000
            if mode == stat.S_IFLNK:
                raise ApiProblem(400, "zip_symlink_forbidden", "ZIP内のシンボリックリンクは使えません。")
            if info.flag_bits & 0x1:
                raise ApiProblem(400, "encrypted_zip_forbidden", "暗号化ZIPは使えません。")
            if info.is_dir():
                continue

            path = PurePosixPath(raw_name).as_posix()
            if path in seen:
                raise ApiProblem(400, "duplicate_zip_path", f"ZIP内に同名ファイルがあります: {path}")
            seen.add(path)

            suffix = PurePosixPath(path).suffix.lower()
            if suffix not in _ALLOWED_SUFFIXES:
                raise ApiProblem(400, "unsupported_file_type", f"MVPではこの種類のファイルは使えません: {path}")
            if info.file_size > MAX_FILE_BYTES:
                raise ApiProblem(413, "file_too_large", f"ZIP内のファイルが大きすぎます: {path}")

            total_uncompressed += info.file_size
            if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
                raise ApiProblem(413, "zip_expands_too_large", "ZIP展開後の合計サイズは8MB以下にしてください。")

            files.append(path)
            if len(files) > MAX_FILE_COUNT:
                raise ApiProblem(413, "too_many_files", "ZIP内のファイル数は100個以下にしてください。")

        if "index.html" not in seen:
            raise ApiProblem(400, "index_missing", "ZIP直下に index.html が必要です。")

        bad_file = archive.testzip()
        if bad_file is not None:
            raise ApiProblem(400, "invalid_zip_crc", f"ZIP内のファイルが破損しています: {bad_file}")

    files.sort()
    return files


def _content_type(path: str) -> str:
    suffix = PurePosixPath(path).suffix.lower()
    explicit = {
        ".html": "text/html; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".mjs": "text/javascript; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".txt": "text/plain; charset=utf-8",
    }
    if suffix in explicit:
        return explicit[suffix]
    guessed, _ = mimetypes.guess_type(path)
    return guessed or "application/octet-stream"


class Phase2AwsBackend(AwsBackend):
    def __init__(
        self,
        *,
        cognito: Any,
        dynamodb: Any,
        s3: Any,
        user_pool_id: str,
        app_client_id: str,
        table_name: str,
        upload_bucket: str,
        published_bucket: str,
    ) -> None:
        super().__init__(
            cognito=cognito,
            dynamodb=dynamodb,
            user_pool_id=user_pool_id,
            app_client_id=app_client_id,
            table_name=table_name,
        )
        self._s3 = s3
        self._upload_bucket = upload_bucket
        self._published_bucket = published_bucket

    @classmethod
    def from_environment(cls) -> "Phase2AwsBackend":
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required outside the AWS Lambda runtime. "
                "Install the development requirements explicitly."
            ) from exc

        return cls(
            cognito=boto3.client("cognito-idp"),
            dynamodb=boto3.client("dynamodb"),
            s3=boto3.client("s3"),
            user_pool_id=_required_env("USER_POOL_ID"),
            app_client_id=_required_env("USER_POOL_CLIENT_ID"),
            table_name=_required_env("DATA_TABLE_NAME"),
            upload_bucket=_required_env("UPLOAD_BUCKET"),
            published_bucket=_required_env("PUBLISHED_BUCKET"),
        )

    def upload_app(
        self,
        auth_subject: str,
        group_id: str,
        title: str,
        filename: str,
        zip_bytes: bytes,
    ) -> dict[str, Any]:
        student = self._user_by_auth_subject(auth_subject)
        self._require_role(student, "student")
        group_name = self._require_active_membership(student.user_id, group_id, "student")
        files = _safe_zip_paths(zip_bytes)

        app_id = uuid.uuid4().hex
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
            "title": _string_attr(title),
            "filename": _string_attr(filename),
            "status": _string_attr("draft"),
            "source_key": _string_attr(source_key),
            "sha256": _string_attr(digest),
            "files_json": _string_attr(json.dumps(files, ensure_ascii=False, separators=(",", ":"))),
            "created_at": _string_attr(created_at),
        }
        app_meta = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("app"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "group_name": _string_attr(group_name),
            "owner_user_id": _string_attr(student.user_id),
            "owner_login_id": _string_attr(student.login_id),
            "title": _string_attr(title),
            "created_at": _string_attr(created_at),
        }
        version = {"pk": _string_attr(f"APP#{app_id}"), "sk": _string_attr(f"VERSION#{version_id}"), **common}
        group_index = {"pk": _string_attr(f"GROUP#{group_id}"), "sk": _string_attr(f"APP#{app_id}#VERSION#{version_id}"), **common}
        user_index = {"pk": _string_attr(f"USER#{student.user_id}"), "sk": _string_attr(f"APP#{app_id}#VERSION#{version_id}"), **common}

        try:
            self._transact_put_new([app_meta, version, group_index, user_index])
        except Exception:
            try:
                self._s3.delete_object(Bucket=self._upload_bucket, Key=source_key)
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "App metadata creation failed after S3 upload, and S3 cleanup also failed."
                ) from cleanup_exc
            raise

        return self._public_version(version)

    def list_my_apps(self, auth_subject: str) -> list[dict[str, Any]]:
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
        apps = [self._public_version(item) for item in self._query_items(response)]
        apps.sort(key=lambda item: item["created_at"], reverse=True)
        return apps

    def submit_app(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        if _item_string(version, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "この作品を公開申請する権限がありません。")
        group_id = _item_string(version, "group_id")
        self._require_active_membership(user.user_id, group_id, "student")
        submitted_at = _now_iso()
        self._transition_version(
            version,
            expected_status="draft",
            new_status="pending_review",
            extra={"submitted_at": submitted_at},
        )
        version["status"] = _string_attr("pending_review")
        version["submitted_at"] = _string_attr(submitted_at)
        return self._public_version(version)

    def list_review_queue(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_teacher_membership(teacher.user_id, group_id)
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}"),
                ":prefix": _string_attr("APP#"),
            },
            ConsistentRead=True,
        )
        queue = [
            self._public_version(item)
            for item in self._query_items(response)
            if _item_string(item, "status") == "pending_review"
        ]
        queue.sort(key=lambda item: item.get("submitted_at", item["created_at"]))
        return queue

    def create_preview(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        owner_user_id = _item_string(version, "owner_user_id")
        group_id = _item_string(version, "group_id")

        if user.user_id == owner_user_id:
            self._require_active_membership(user.user_id, group_id, "student")
        else:
            self._require_teacher_membership(user.user_id, group_id)

        token = secrets.token_urlsafe(32)
        expires_at = int(time.time()) + PREVIEW_TTL_SECONDS
        item = {
            "pk": _string_attr(f"PREVIEW#{token}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("preview_token"),
            "source_key": _string_attr(_item_string(version, "source_key")),
            "sha256": _string_attr(_item_string(version, "sha256")),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "expires_at": _number_attr(expires_at),
        }
        self._transact_put_new([item])
        return {
            "content_path": f"/content/{token}/index.html",
            "expires_in": PREVIEW_TTL_SECONDS,
        }

    def approve_app(self, auth_subject: str, app_id: str, version_id: str) -> dict[str, Any]:
        teacher = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        group_id = _item_string(version, "group_id")
        self._require_teacher_membership(teacher.user_id, group_id)
        if _item_string(version, "status") != "pending_review":
            raise ApiProblem(409, "invalid_app_state", "公開申請中の作品だけ承認できます。")

        source_key = _item_string(version, "source_key")
        published_key = f"groups/{group_id}/apps/{app_id}/versions/{version_id}/source.zip"
        self._s3.copy_object(
            Bucket=self._published_bucket,
            Key=published_key,
            CopySource={"Bucket": self._upload_bucket, "Key": source_key},
            ContentType="application/zip",
            MetadataDirective="REPLACE",
            Metadata={"sha256": _item_string(version, "sha256")},
        )

        reviewed_at = _now_iso()
        try:
            self._transition_version(
                version,
                expected_status="pending_review",
                new_status="approved",
                extra={
                    "published_key": published_key,
                    "reviewed_at": reviewed_at,
                    "reviewed_by": teacher.user_id,
                },
            )
        except Exception:
            try:
                self._s3.delete_object(Bucket=self._published_bucket, Key=published_key)
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Approval metadata update failed after S3 publish copy, and published object cleanup also failed."
                ) from cleanup_exc
            raise

        version["status"] = _string_attr("approved")
        version["published_key"] = _string_attr(published_key)
        version["reviewed_at"] = _string_attr(reviewed_at)
        return self._public_version(version)

    def get_preview_file(self, token: str, path: str) -> tuple[bytes, str]:
        item = self._get_item(pk=f"PREVIEW#{token}", sk="META")
        if item is None:
            raise ApiProblem(404, "preview_not_found", "プレビューURLが無効です。")
        if _item_number(item, "expires_at") < int(time.time()):
            raise ApiProblem(404, "preview_expired", "プレビューURLの有効期限が切れました。")

        normalized = self._normalize_content_path(path)
        source_key = _item_string(item, "source_key")
        response = self._s3.get_object(Bucket=self._upload_bucket, Key=source_key)
        body = response.get("Body")
        if body is None or not hasattr(body, "read"):
            raise RuntimeError("S3 GetObject response has no readable Body")
        zip_bytes = body.read(MAX_ZIP_BYTES + 1)
        if not isinstance(zip_bytes, bytes):
            raise RuntimeError("S3 Body.read() did not return bytes")
        if len(zip_bytes) > MAX_ZIP_BYTES:
            raise RuntimeError("Stored ZIP exceeds configured maximum size")
        if hashlib.sha256(zip_bytes).hexdigest() != _item_string(item, "sha256"):
            raise RuntimeError("Stored ZIP hash does not match app metadata")

        try:
            with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
                names = set(_safe_zip_paths(zip_bytes))
                if normalized not in names:
                    raise ApiProblem(404, "preview_file_not_found", "プレビュー内のファイルが見つかりません。")
                data = archive.read(normalized)
        except zipfile.BadZipFile as exc:
            raise RuntimeError("Stored app ZIP became unreadable") from exc

        if len(data) > MAX_FILE_BYTES:
            raise RuntimeError("Stored preview file exceeds configured maximum size")
        return data, _content_type(normalized)

    def _require_active_membership(self, user_id: str, group_id: str, role: str) -> str:
        item = self._get_item(pk=f"GROUP#{group_id}", sk=f"MEMBER#{user_id}")
        if item is None:
            raise ApiProblem(403, "forbidden", "このグループを利用する権限がありません。")
        if _item_string(item, "role") != role or _item_string(item, "status") != "active":
            raise ApiProblem(403, "forbidden", "このグループを利用する権限がありません。")
        return _item_string(item, "group_name")

    def _version_item(self, app_id: str, version_id: str) -> dict[str, Any]:
        item = self._get_item(pk=f"APP#{app_id}", sk=f"VERSION#{version_id}")
        if item is None:
            raise ApiProblem(404, "app_version_not_found", "指定された作品が見つかりません。")
        return item

    def _transition_version(
        self,
        version: dict[str, Any],
        *,
        expected_status: str,
        new_status: str,
        extra: dict[str, str],
    ) -> None:
        if _item_string(version, "status") != expected_status:
            raise ApiProblem(409, "invalid_app_state", "作品の状態がこの操作に対応していません。")

        app_id = _item_string(version, "app_id")
        version_id = _item_string(version, "version_id")
        group_id = _item_string(version, "group_id")
        owner_user_id = _item_string(version, "owner_user_id")

        names = {"#status": "status"}
        values: dict[str, dict[str, str]] = {
            ":expected": _string_attr(expected_status),
            ":next": _string_attr(new_status),
        }
        assignments = ["#status = :next"]
        for index, (name, value) in enumerate(extra.items()):
            name_key = f"#x{index}"
            value_key = f":x{index}"
            names[name_key] = name
            values[value_key] = _string_attr(value)
            assignments.append(f"{name_key} = {value_key}")

        update = "SET " + ", ".join(assignments)
        keys = [
            (f"APP#{app_id}", f"VERSION#{version_id}"),
            (f"GROUP#{group_id}", f"APP#{app_id}#VERSION#{version_id}"),
            (f"USER#{owner_user_id}", f"APP#{app_id}#VERSION#{version_id}"),
        ]
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": self._table_name,
                        "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                        "UpdateExpression": update,
                        "ConditionExpression": "#status = :expected",
                        "ExpressionAttributeNames": names,
                        "ExpressionAttributeValues": values,
                    }
                }
                for pk, sk in keys
            ]
        )

    @staticmethod
    def _normalize_content_path(path: str) -> str:
        if not isinstance(path, str) or not path or "\\" in path or "\x00" in path:
            raise ApiProblem(404, "preview_file_not_found", "プレビュー内のファイルが見つかりません。")
        if path.startswith("/"):
            path = path[1:]
        parts = path.split("/")
        if any(part in {"", ".", ".."} for part in parts):
            raise ApiProblem(404, "preview_file_not_found", "プレビュー内のファイルが見つかりません。")
        return PurePosixPath(*parts).as_posix()

    @staticmethod
    def _public_version(item: dict[str, Any]) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "app_id": _item_string(item, "app_id"),
            "version_id": _item_string(item, "version_id"),
            "group_id": _item_string(item, "group_id"),
            "group_name": _item_string(item, "group_name"),
            "owner_user_id": _item_string(item, "owner_user_id"),
            "owner_login_id": _item_string(item, "owner_login_id"),
            "title": _item_string(item, "title"),
            "filename": _item_string(item, "filename"),
            "status": _item_string(item, "status"),
            "created_at": _item_string(item, "created_at"),
        }
        for key in ("submitted_at", "reviewed_at"):
            raw = item.get(key)
            if isinstance(raw, dict) and isinstance(raw.get("S"), str):
                payload[key] = raw["S"]
        return payload
