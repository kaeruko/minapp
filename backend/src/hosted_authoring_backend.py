from __future__ import annotations

import hashlib
import json
import math
import re
import uuid
from pathlib import PurePosixPath
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import _optional_number, _optional_string
from hosted_platform_backend import _now_iso, _number_attr
from hosted_preview_state_backend import HostedPreviewStateBackend

MAX_AUTHORING_DOCUMENT_BYTES = 512 * 1024
MAX_AUTHORING_ASSET_BYTES = 8 * 1024 * 1024
MAX_AUTHORING_ASSET_COUNT = 100
MAX_AUTHORING_ASSET_TOTAL_BYTES = 32 * 1024 * 1024
MAX_AUTHORING_REVISIONS = 100

_CONTENT_FORMAT_RE = re.compile(
    r"^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$"
)
_CONTENT_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_AUTHORING_ASSET_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
}


class AuthoringCommitCleanupError(RuntimeError):
    def __init__(self, original_error: BaseException, cleanup_error: BaseException) -> None:
        super().__init__(
            "Authoring metadata commit failed and cleanup of the newly written "
            f"immutable object also failed: original={original_error!r}; cleanup={cleanup_error!r}"
        )
        self.original_error = original_error
        self.cleanup_error = cleanup_error


class HostedAuthoringBackend(HostedPreviewStateBackend):
    """Structured Authoring Project storage for editable content.

    ZIP remains an import/publish boundary. Draft document/assets are immutable
    per-revision objects and DynamoDB advances the current draft revision only
    through optimistic concurrency.
    """

    def create_authoring_project(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        content_format = validate_content_format(content_format)
        document_bytes = _document_bytes(document)
        user = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(user.user_id, group_id)

        content_id = uuid.uuid4().hex
        revision = 1
        created_at = _now_iso()
        document_key = self._document_key(group_id, content_id, revision)
        document_sha256 = hashlib.sha256(document_bytes).hexdigest()
        assets: dict[str, dict[str, Any]] = {}

        self._put_immutable_object(
            key=document_key,
            data=document_bytes,
            content_type="application/json; charset=utf-8",
            sha256=document_sha256,
        )

        meta = {
            "pk": _string_attr(f"CONTENT#{content_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("authoring_content"),
            "content_id": _string_attr(content_id),
            "group_id": _string_attr(group_id),
            "owner_user_id": _string_attr(user.user_id),
            "content_format": _string_attr(content_format),
            "status": _string_attr("draft"),
            "draft_revision": _number_attr(revision),
            "document_key": _string_attr(document_key),
            "document_sha256": _string_attr(document_sha256),
            "document_bytes": _number_attr(len(document_bytes)),
            "assets_json": _string_attr(_assets_json(assets)),
            "created_at": _string_attr(created_at),
            "updated_at": _string_attr(created_at),
        }
        manifest = self._revision_manifest(meta, revision=revision, created_at=created_at)
        try:
            self._transact_put_new([meta, manifest])
        except Exception as original_error:
            self._cleanup_after_failed_commit(document_key, original_error)
            raise
        return self._public_project(meta)

    def load_authoring_project(
        self,
        auth_subject: str,
        content_id: str,
    ) -> dict[str, Any]:
        _, item = self._owned_content(auth_subject, content_id)
        document_bytes = self._read_object(
            key=_item_string(item, "document_key"),
            expected_sha256=_item_string(item, "document_sha256"),
            max_bytes=MAX_AUTHORING_DOCUMENT_BYTES,
        )
        try:
            document = json.loads(document_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError("Stored Authoring document is not valid UTF-8 JSON") from exc
        _validate_json_value(document, "document")
        if not isinstance(document, dict):
            raise RuntimeError("Stored Authoring document root is not a JSON object")
        result = self._public_project(item)
        result["document"] = document
        return result

    def get_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        path: str,
    ) -> tuple[bytes, str]:
        path = validate_authoring_asset_path(path)
        _, item = self._owned_content(auth_subject, content_id)
        assets = _item_assets(item)
        asset = assets.get(path)
        if asset is None:
            raise ApiProblem(404, "authoring_asset_not_found", "Authoring asset was not found.")
        data = self._read_object(
            key=_asset_manifest_string(asset, "key"),
            expected_sha256=_asset_manifest_string(asset, "sha256"),
            max_bytes=MAX_AUTHORING_ASSET_BYTES,
        )
        if len(data) != _asset_manifest_int(asset, "bytes"):
            raise RuntimeError("Stored Authoring asset size does not match metadata")
        return data, _asset_manifest_string(asset, "content_type")

    def save_authoring_document(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        expected_revision = _validate_expected_revision(expected_revision)
        document_bytes = _document_bytes(document)
        _, current = self._owned_content(auth_subject, content_id)
        self._require_expected_revision(current, expected_revision)
        next_revision = self._next_revision(expected_revision)

        group_id = _item_string(current, "group_id")
        document_key = self._document_key(group_id, content_id, next_revision)
        document_sha256 = hashlib.sha256(document_bytes).hexdigest()
        self._put_immutable_object(
            key=document_key,
            data=document_bytes,
            content_type="application/json; charset=utf-8",
            sha256=document_sha256,
        )

        updated_at = _now_iso()
        replacement = dict(current)
        replacement["draft_revision"] = _number_attr(next_revision)
        replacement["document_key"] = _string_attr(document_key)
        replacement["document_sha256"] = _string_attr(document_sha256)
        replacement["document_bytes"] = _number_attr(len(document_bytes))
        replacement["updated_at"] = _string_attr(updated_at)
        manifest = self._revision_manifest(
            replacement,
            revision=next_revision,
            created_at=updated_at,
        )
        self._commit_revision(
            content_id=content_id,
            expected_revision=expected_revision,
            next_revision=next_revision,
            update_fields={
                "document_key": _string_attr(document_key),
                "document_sha256": _string_attr(document_sha256),
                "document_bytes": _number_attr(len(document_bytes)),
                "updated_at": _string_attr(updated_at),
            },
            manifest=manifest,
            cleanup_key=document_key,
        )
        return self._public_project(replacement)

    def save_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
        data: bytes,
    ) -> dict[str, Any]:
        expected_revision = _validate_expected_revision(expected_revision)
        path = validate_authoring_asset_path(path)
        if not isinstance(data, bytes):
            raise TypeError("Authoring asset data must be bytes")
        if not data:
            raise ApiProblem(400, "empty_authoring_asset", "Authoring asset must not be empty.")
        if len(data) > MAX_AUTHORING_ASSET_BYTES:
            raise ApiProblem(
                413,
                "authoring_asset_too_large",
                f"Authoring asset must be at most {MAX_AUTHORING_ASSET_BYTES} bytes.",
            )

        _, current = self._owned_content(auth_subject, content_id)
        self._require_expected_revision(current, expected_revision)
        next_revision = self._next_revision(expected_revision)
        assets = _item_assets(current)
        previous = assets.get(path)
        if previous is None and len(assets) >= MAX_AUTHORING_ASSET_COUNT:
            raise ApiProblem(
                409,
                "authoring_asset_count_limit_reached",
                f"Authoring Project supports at most {MAX_AUTHORING_ASSET_COUNT} assets.",
            )
        current_total = sum(_asset_manifest_int(asset, "bytes") for asset in assets.values())
        previous_bytes = 0 if previous is None else _asset_manifest_int(previous, "bytes")
        next_total = current_total - previous_bytes + len(data)
        if next_total > MAX_AUTHORING_ASSET_TOTAL_BYTES:
            raise ApiProblem(
                413,
                "authoring_asset_storage_limit_reached",
                f"Authoring assets must total at most {MAX_AUTHORING_ASSET_TOTAL_BYTES} bytes.",
            )

        group_id = _item_string(current, "group_id")
        object_key = self._asset_key(group_id, content_id, next_revision, path)
        sha256 = hashlib.sha256(data).hexdigest()
        content_type = _AUTHORING_ASSET_TYPES[PurePosixPath(path).suffix.lower()]
        self._put_immutable_object(
            key=object_key,
            data=data,
            content_type=content_type,
            sha256=sha256,
        )

        updated_at = _now_iso()
        assets[path] = {
            "key": object_key,
            "sha256": sha256,
            "bytes": len(data),
            "content_type": content_type,
            "revision": next_revision,
        }
        assets_json = _assets_json(assets)
        replacement = dict(current)
        replacement["draft_revision"] = _number_attr(next_revision)
        replacement["assets_json"] = _string_attr(assets_json)
        replacement["updated_at"] = _string_attr(updated_at)
        manifest = self._revision_manifest(
            replacement,
            revision=next_revision,
            created_at=updated_at,
        )
        self._commit_revision(
            content_id=content_id,
            expected_revision=expected_revision,
            next_revision=next_revision,
            update_fields={
                "assets_json": _string_attr(assets_json),
                "updated_at": _string_attr(updated_at),
            },
            manifest=manifest,
            cleanup_key=object_key,
        )
        return self._public_project(replacement)

    def delete_authoring_asset(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
        path: str,
    ) -> dict[str, Any]:
        expected_revision = _validate_expected_revision(expected_revision)
        path = validate_authoring_asset_path(path)
        _, current = self._owned_content(auth_subject, content_id)
        self._require_expected_revision(current, expected_revision)
        assets = _item_assets(current)
        if path not in assets:
            raise ApiProblem(404, "authoring_asset_not_found", "Authoring asset was not found.")
        del assets[path]
        next_revision = self._next_revision(expected_revision)
        updated_at = _now_iso()
        assets_json = _assets_json(assets)
        replacement = dict(current)
        replacement["draft_revision"] = _number_attr(next_revision)
        replacement["assets_json"] = _string_attr(assets_json)
        replacement["updated_at"] = _string_attr(updated_at)
        manifest = self._revision_manifest(
            replacement,
            revision=next_revision,
            created_at=updated_at,
        )
        self._commit_revision(
            content_id=content_id,
            expected_revision=expected_revision,
            next_revision=next_revision,
            update_fields={
                "assets_json": _string_attr(assets_json),
                "updated_at": _string_attr(updated_at),
            },
            manifest=manifest,
            cleanup_key=None,
        )
        return self._public_project(replacement)

    def _owned_content(
        self,
        auth_subject: str,
        content_id: str,
    ) -> tuple[Any, dict[str, Any]]:
        _validate_content_id(content_id)
        user = self._user_by_auth_subject(auth_subject)
        item = self._get_item(pk=f"CONTENT#{content_id}", sk="META")
        if item is None:
            raise ApiProblem(404, "content_not_found", "Authoring content was not found.")
        group_id = _item_string(item, "group_id")
        self._require_owner_group(user.user_id, group_id)
        if _item_string(item, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "You do not own this Authoring content.")
        status = _item_string(item, "status")
        if status != "draft":
            raise ApiProblem(409, "content_not_editable", "Authoring content is not editable.")
        return user, item

    @staticmethod
    def _require_expected_revision(item: dict[str, Any], expected_revision: int) -> None:
        current = _optional_number(item, "draft_revision")
        if current != expected_revision:
            raise ApiProblem(
                409,
                "revision_conflict",
                f"Expected draft revision {expected_revision}, current revision is {current}.",
            )

    @staticmethod
    def _next_revision(expected_revision: int) -> int:
        if expected_revision >= MAX_AUTHORING_REVISIONS:
            raise ApiProblem(
                409,
                "authoring_revision_limit_reached",
                f"Authoring Project supports at most {MAX_AUTHORING_REVISIONS} revisions.",
            )
        return expected_revision + 1

    def _commit_revision(
        self,
        *,
        content_id: str,
        expected_revision: int,
        next_revision: int,
        update_fields: dict[str, dict[str, str]],
        manifest: dict[str, Any],
        cleanup_key: str | None,
    ) -> None:
        names = {f"#f{index}": field for index, field in enumerate(update_fields)}
        values: dict[str, dict[str, str]] = {
            ":expected_revision": _number_attr(expected_revision),
            ":next_revision": _number_attr(next_revision),
        }
        assignments = ["draft_revision = :next_revision"]
        for index, value in enumerate(update_fields.values()):
            value_name = f":f{index}"
            values[value_name] = value
            assignments.append(f"#f{index} = {value_name}")

        try:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"CONTENT#{content_id}"),
                                "sk": _string_attr("META"),
                            },
                            "UpdateExpression": "SET " + ", ".join(assignments),
                            "ConditionExpression": (
                                "draft_revision = :expected_revision AND "
                                "attribute_not_exists(deletion_state)"
                            ),
                            "ExpressionAttributeNames": names,
                            "ExpressionAttributeValues": values,
                        }
                    },
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": manifest,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                ]
            )
        except Exception as original_error:
            if cleanup_key is not None:
                self._cleanup_after_failed_commit(cleanup_key, original_error)
            if _aws_error_code(original_error) == "TransactionCanceledException":
                raise ApiProblem(
                    409,
                    "revision_conflict",
                    f"Draft revision {expected_revision} is no longer current.",
                ) from original_error
            raise

    def _revision_manifest(
        self,
        item: dict[str, Any],
        *,
        revision: int,
        created_at: str,
    ) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"CONTENT#{_item_string(item, 'content_id')}"),
            "sk": _string_attr(f"REVISION#{revision:06d}"),
            "entity": _string_attr("authoring_revision"),
            "content_id": _string_attr(_item_string(item, "content_id")),
            "group_id": _string_attr(_item_string(item, "group_id")),
            "owner_user_id": _string_attr(_item_string(item, "owner_user_id")),
            "content_format": _string_attr(_item_string(item, "content_format")),
            "revision": _number_attr(revision),
            "document_key": _string_attr(_item_string(item, "document_key")),
            "document_sha256": _string_attr(_item_string(item, "document_sha256")),
            "document_bytes": _number_attr(_required_item_number(item, "document_bytes")),
            "assets_json": _string_attr(_item_string(item, "assets_json")),
            "created_at": _string_attr(created_at),
        }

    def _put_immutable_object(
        self,
        *,
        key: str,
        data: bytes,
        content_type: str,
        sha256: str,
    ) -> None:
        try:
            self._s3.put_object(
                Bucket=self._upload_bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
                Metadata={"sha256": sha256},
                IfNoneMatch="*",
            )
        except Exception as exc:
            if _aws_error_code(exc) in {"PreconditionFailed", "ConditionalRequestConflict"}:
                raise RuntimeError(
                    f"Immutable Authoring object already exists unexpectedly: {key}"
                ) from exc
            raise

    def _read_object(
        self,
        *,
        key: str,
        expected_sha256: str,
        max_bytes: int,
    ) -> bytes:
        response = self._s3.get_object(Bucket=self._upload_bucket, Key=key)
        body = response.get("Body")
        if body is None or not hasattr(body, "read"):
            raise RuntimeError("S3 GetObject response has no readable Body")
        data = body.read(max_bytes + 1)
        if not isinstance(data, bytes):
            raise RuntimeError("S3 Body.read() did not return bytes")
        if len(data) > max_bytes:
            raise RuntimeError("Stored Authoring object exceeds its configured maximum size")
        if hashlib.sha256(data).hexdigest() != expected_sha256:
            raise RuntimeError("Stored Authoring object hash does not match metadata")
        return data

    def _cleanup_after_failed_commit(
        self,
        key: str,
        original_error: BaseException,
    ) -> None:
        try:
            self._s3.delete_object(Bucket=self._upload_bucket, Key=key)
        except Exception as cleanup_error:
            raise AuthoringCommitCleanupError(original_error, cleanup_error) from cleanup_error

    @staticmethod
    def _document_key(group_id: str, content_id: str, revision: int) -> str:
        return f"authoring/{group_id}/{content_id}/revisions/{revision:06d}/document.json"

    @staticmethod
    def _asset_key(
        group_id: str,
        content_id: str,
        revision: int,
        path: str,
    ) -> str:
        return f"authoring/{group_id}/{content_id}/revisions/{revision:06d}/assets/{path}"

    @staticmethod
    def _public_project(item: dict[str, Any]) -> dict[str, Any]:
        return {
            "content_id": _item_string(item, "content_id"),
            "group_id": _item_string(item, "group_id"),
            "content_format": _item_string(item, "content_format"),
            "status": _item_string(item, "status"),
            "draft_revision": _required_item_number(item, "draft_revision"),
            "assets": _public_assets(_item_assets(item)),
            "created_at": _item_string(item, "created_at"),
            "updated_at": _item_string(item, "updated_at"),
        }


def validate_content_format(content_format: str) -> str:
    if not isinstance(content_format, str):
        raise TypeError("content_format must be a string")
    if _CONTENT_FORMAT_RE.fullmatch(content_format) is None:
        raise ApiProblem(
            400,
            "invalid_content_format",
            "content_format must be a namespaced version such as minapp/novel@1.",
        )
    return content_format


def validate_authoring_asset_path(path: str) -> str:
    if not isinstance(path, str):
        raise TypeError("Authoring asset path must be a string")
    if not path or len(path) > 256 or "\\" in path or "\x00" in path or path.startswith("/"):
        raise ApiProblem(400, "invalid_authoring_asset_path", "Authoring asset path is invalid.")
    parts = path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ApiProblem(400, "invalid_authoring_asset_path", "Authoring asset path is invalid.")
    normalized = PurePosixPath(*parts).as_posix()
    suffix = PurePosixPath(normalized).suffix.lower()
    if suffix not in _AUTHORING_ASSET_TYPES:
        raise ApiProblem(
            400,
            "unsupported_authoring_asset_type",
            f"Authoring asset type is not supported: {normalized}",
        )
    return normalized


def _document_bytes(document: dict[str, Any]) -> bytes:
    if not isinstance(document, dict):
        raise ApiProblem(400, "invalid_master_data", "Master Data root must be a JSON object.")
    _validate_json_value(document, "document")
    try:
        encoded = json.dumps(
            document,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise ApiProblem(400, "invalid_master_data", "Master Data must be strict JSON.") from exc
    if len(encoded) > MAX_AUTHORING_DOCUMENT_BYTES:
        raise ApiProblem(
            413,
            "authoring_document_too_large",
            f"Master Data must be at most {MAX_AUTHORING_DOCUMENT_BYTES} bytes.",
        )
    return encoded


def _validate_json_value(value: Any, path: str) -> None:
    if value is None or isinstance(value, (bool, str, int)):
        return
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ApiProblem(400, "invalid_master_data", f"{path} contains a non-finite number.")
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            _validate_json_value(child, f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ApiProblem(400, "invalid_master_data", f"{path} contains a non-string object key.")
            _validate_json_value(child, f"{path}.{key}")
        return
    raise ApiProblem(400, "invalid_master_data", f"{path} contains a non-JSON value.")


def _validate_expected_revision(value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ApiProblem(400, "invalid_expected_revision", "expected_revision must be a positive integer.")
    return value


def _validate_content_id(content_id: str) -> None:
    if not isinstance(content_id, str) or _CONTENT_ID_RE.fullmatch(content_id) is None:
        raise ApiProblem(404, "content_not_found", "Authoring content was not found.")


def _assets_json(assets: dict[str, dict[str, Any]]) -> str:
    return json.dumps(assets, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _item_assets(item: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = _item_string(item, "assets_json")
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Stored Authoring assets_json is invalid JSON") from exc
    if not isinstance(decoded, dict):
        raise RuntimeError("Stored Authoring assets_json is not an object")
    result: dict[str, dict[str, Any]] = {}
    for path, asset in decoded.items():
        if not isinstance(path, str) or not isinstance(asset, dict):
            raise RuntimeError("Stored Authoring asset manifest is malformed")
        validate_authoring_asset_path(path)
        _asset_manifest_string(asset, "key")
        _asset_manifest_string(asset, "sha256")
        _asset_manifest_int(asset, "bytes")
        _asset_manifest_string(asset, "content_type")
        _asset_manifest_int(asset, "revision")
        result[path] = dict(asset)
    return result


def _public_assets(assets: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "path": path,
            "sha256": _asset_manifest_string(asset, "sha256"),
            "bytes": _asset_manifest_int(asset, "bytes"),
            "content_type": _asset_manifest_string(asset, "content_type"),
            "revision": _asset_manifest_int(asset, "revision"),
        }
        for path, asset in sorted(assets.items())
    ]


def _asset_manifest_string(asset: dict[str, Any], key: str) -> str:
    value = asset.get(key)
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"Stored Authoring asset manifest has invalid {key}")
    return value


def _asset_manifest_int(asset: dict[str, Any], key: str) -> int:
    value = asset.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise RuntimeError(f"Stored Authoring asset manifest has invalid {key}")
    return value


def _required_item_number(item: dict[str, Any], key: str) -> int:
    value = _optional_number(item, key)
    if value is None:
        raise RuntimeError(f"DynamoDB item is missing number attribute {key!r}")
    return value
