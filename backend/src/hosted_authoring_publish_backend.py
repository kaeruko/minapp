from __future__ import annotations

import hashlib
import json
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_backend import (
    MAX_AUTHORING_ASSET_BYTES,
    MAX_AUTHORING_DOCUMENT_BYTES,
    HostedAuthoringBackend,
    _asset_manifest_int,
    _asset_manifest_string,
    _assets_json,
    _document_bytes,
    _item_assets,
    _public_assets,
    _required_item_number,
    _validate_content_id,
    _validate_expected_revision,
)
from hosted_catalog_backend import _optional_number
from hosted_platform_backend import _now_iso, _number_attr

MAX_AUTHORING_PUBLISHED_VERSIONS = 20


class AuthoringPublishCleanupError(RuntimeError):
    def __init__(self, original_error: BaseException, cleanup_error: BaseException) -> None:
        super().__init__(
            "Authoring publish failed and cleanup of an uncommitted published object "
            f"also failed: original={original_error!r}; cleanup={cleanup_error!r}"
        )
        self.original_error = original_error
        self.cleanup_error = cleanup_error


class HostedAuthoringPublishBackend(HostedAuthoringBackend):
    """Materializes immutable Authoring revisions, then advances a publish pointer."""

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
        self._require_active_membership(user.user_id, group_id)
        if _item_string(item, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "You do not own this Authoring content.")
        status = _item_string(item, "status")
        if status != "draft":
            raise ApiProblem(409, "content_not_editable", "Authoring content is not editable.")
        return user, item

    def publish_authoring_project(
        self,
        auth_subject: str,
        content_id: str,
        *,
        expected_revision: int,
    ) -> dict[str, Any]:
        expected_revision = _validate_expected_revision(expected_revision)
        _, current = self._owned_content(auth_subject, content_id)
        self._require_expected_revision(current, expected_revision)

        previous_version = _optional_number(current, "published_version") or 0
        previous_revision = _optional_number(current, "published_revision")
        if previous_revision == expected_revision:
            raise ApiProblem(
                409,
                "draft_already_published",
                "The current Authoring draft revision is already published.",
            )
        if previous_version >= MAX_AUTHORING_PUBLISHED_VERSIONS:
            raise ApiProblem(
                409,
                "authoring_publish_limit_reached",
                f"Authoring content supports at most {MAX_AUTHORING_PUBLISHED_VERSIONS} published versions.",
            )
        next_version = previous_version + 1

        source = self._get_item(
            pk=f"CONTENT#{content_id}",
            sk=f"REVISION#{expected_revision:06d}",
        )
        if source is None:
            raise RuntimeError("Current Authoring revision manifest is missing")
        self._validate_source_manifest(current, source, expected_revision)

        document_bytes = self._read_object(
            key=_item_string(source, "document_key"),
            expected_sha256=_item_string(source, "document_sha256"),
            max_bytes=MAX_AUTHORING_DOCUMENT_BYTES,
        )
        try:
            document = json.loads(document_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError("Authoring revision document is not valid UTF-8 JSON") from exc
        if not isinstance(document, dict) or _document_bytes(document) != document_bytes:
            raise RuntimeError("Authoring revision document is not canonical Master Data")

        source_assets = _item_assets(source)
        asset_bytes: dict[str, bytes] = {}
        for path, asset in source_assets.items():
            data = self._read_object(
                key=_asset_manifest_string(asset, "key"),
                expected_sha256=_asset_manifest_string(asset, "sha256"),
                max_bytes=MAX_AUTHORING_ASSET_BYTES,
            )
            if len(data) != _asset_manifest_int(asset, "bytes"):
                raise RuntimeError("Authoring revision asset size does not match manifest")
            asset_bytes[path] = data

        group_id = _item_string(current, "group_id")
        content_format = _item_string(current, "content_format")
        written: list[tuple[str, str]] = []
        try:
            document_key = self._published_document_key(
                group_id,
                content_id,
                next_version,
            )
            document_sha256 = hashlib.sha256(document_bytes).hexdigest()
            written.append(
                (
                    document_key,
                    self._put_published_object(
                        key=document_key,
                        data=document_bytes,
                        content_type="application/json; charset=utf-8",
                        sha256=document_sha256,
                    ),
                )
            )

            published_assets: dict[str, dict[str, Any]] = {}
            for path in sorted(source_assets):
                source_asset = source_assets[path]
                data = asset_bytes[path]
                key = self._published_asset_key(
                    group_id,
                    content_id,
                    next_version,
                    path,
                )
                sha256 = _asset_manifest_string(source_asset, "sha256")
                content_type = _asset_manifest_string(source_asset, "content_type")
                written.append(
                    (
                        key,
                        self._put_published_object(
                            key=key,
                            data=data,
                            content_type=content_type,
                            sha256=sha256,
                        ),
                    )
                )
                published_assets[path] = {
                    "key": key,
                    "sha256": sha256,
                    "bytes": len(data),
                    "content_type": content_type,
                    "revision": _asset_manifest_int(source_asset, "revision"),
                }

            verified_document = self._read_published_object(
                key=document_key,
                expected_sha256=document_sha256,
                max_bytes=MAX_AUTHORING_DOCUMENT_BYTES,
            )
            if verified_document != document_bytes:
                raise RuntimeError("Published Authoring document changed during materialization")
            for path, asset in published_assets.items():
                verified_asset = self._read_published_object(
                    key=_asset_manifest_string(asset, "key"),
                    expected_sha256=_asset_manifest_string(asset, "sha256"),
                    max_bytes=MAX_AUTHORING_ASSET_BYTES,
                )
                if len(verified_asset) != _asset_manifest_int(asset, "bytes"):
                    raise RuntimeError(f"Published Authoring asset size mismatch: {path}")

            published_at = _now_iso()
            manifest = {
                "pk": _string_attr(f"CONTENT#{content_id}"),
                "sk": _string_attr(f"PUBLISHED#{next_version:06d}"),
                "entity": _string_attr("authoring_published_version"),
                "content_id": _string_attr(content_id),
                "group_id": _string_attr(group_id),
                "owner_user_id": _string_attr(_item_string(current, "owner_user_id")),
                "content_format": _string_attr(content_format),
                "published_version": _number_attr(next_version),
                "source_revision": _number_attr(expected_revision),
                "document_key": _string_attr(document_key),
                "document_sha256": _string_attr(document_sha256),
                "document_bytes": _number_attr(len(document_bytes)),
                "assets_json": _string_attr(_assets_json(published_assets)),
                "published_at": _string_attr(published_at),
            }
            self._commit_publish_pointer(
                content_id=content_id,
                expected_revision=expected_revision,
                previous_version=previous_version,
                next_version=next_version,
                published_at=published_at,
                manifest=manifest,
            )
        except Exception as original_error:
            self._cleanup_uncommitted_published(written, original_error)
            raise

        return {
            "content_id": content_id,
            "group_id": group_id,
            "content_format": content_format,
            "published_version": next_version,
            "source_revision": expected_revision,
            "assets": _public_assets(published_assets),
            "published_at": published_at,
        }

    def _commit_publish_pointer(
        self,
        *,
        content_id: str,
        expected_revision: int,
        previous_version: int,
        next_version: int,
        published_at: str,
        manifest: dict[str, Any],
    ) -> None:
        values = {
            ":expected_revision": _number_attr(expected_revision),
            ":next_version": _number_attr(next_version),
            ":published_revision": _number_attr(expected_revision),
            ":published_at": _string_attr(published_at),
        }
        if previous_version == 0:
            pointer_condition = "attribute_not_exists(published_version)"
        else:
            pointer_condition = "published_version = :previous_version"
            values[":previous_version"] = _number_attr(previous_version)
        try:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": manifest,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                    {
                        "Update": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"CONTENT#{content_id}"),
                                "sk": _string_attr("META"),
                            },
                            "UpdateExpression": (
                                "SET published_version = :next_version, "
                                "published_revision = :published_revision, "
                                "published_at = :published_at"
                            ),
                            "ConditionExpression": (
                                "draft_revision = :expected_revision AND "
                                "attribute_not_exists(deletion_state) AND "
                                f"{pointer_condition}"
                            ),
                            "ExpressionAttributeValues": values,
                        }
                    },
                ]
            )
        except Exception as exc:
            if _aws_error_code(exc) == "TransactionCanceledException":
                raise ApiProblem(
                    409,
                    "publish_conflict",
                    "Authoring content changed while publish was being committed.",
                ) from exc
            raise

    def _put_published_object(
        self,
        *,
        key: str,
        data: bytes,
        content_type: str,
        sha256: str,
    ) -> str:
        try:
            response = self._s3.put_object(
                Bucket=self._published_bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
                Metadata={"sha256": sha256},
                IfNoneMatch="*",
            )
        except Exception as exc:
            if _aws_error_code(exc) in {"PreconditionFailed", "ConditionalRequestConflict"}:
                raise RuntimeError(
                    f"Immutable Authoring published object already exists: {key}"
                ) from exc
            raise
        version_id = response.get("VersionId")
        if not isinstance(version_id, str) or not version_id:
            try:
                self._s3.delete_object(Bucket=self._published_bucket, Key=key)
            except Exception as cleanup_error:
                raise RuntimeError(
                    "Published Authoring write returned no S3 VersionId and cleanup failed"
                ) from cleanup_error
            raise RuntimeError("Published Authoring write returned no S3 VersionId")
        return version_id

    def _read_published_object(
        self,
        *,
        key: str,
        expected_sha256: str,
        max_bytes: int,
    ) -> bytes:
        response = self._s3.get_object(Bucket=self._published_bucket, Key=key)
        body = response.get("Body")
        if body is None or not hasattr(body, "read"):
            raise RuntimeError("Published S3 GetObject response has no readable Body")
        data = body.read(max_bytes + 1)
        if not isinstance(data, bytes):
            raise RuntimeError("Published S3 Body.read() did not return bytes")
        if len(data) > max_bytes:
            raise RuntimeError("Published Authoring object exceeds its maximum size")
        if hashlib.sha256(data).hexdigest() != expected_sha256:
            raise RuntimeError("Published Authoring object hash does not match manifest")
        return data

    def _cleanup_uncommitted_published(
        self,
        written: list[tuple[str, str]],
        original_error: BaseException,
    ) -> None:
        for key, version_id in reversed(written):
            try:
                self._s3.delete_object(
                    Bucket=self._published_bucket,
                    Key=key,
                    VersionId=version_id,
                )
            except Exception as cleanup_error:
                raise AuthoringPublishCleanupError(
                    original_error,
                    cleanup_error,
                ) from cleanup_error

    @staticmethod
    def _validate_source_manifest(
        current: dict[str, Any],
        source: dict[str, Any],
        revision: int,
    ) -> None:
        if _item_string(source, "entity") != "authoring_revision":
            raise RuntimeError("Authoring revision manifest has an unexpected entity")
        for field in ("content_id", "group_id", "owner_user_id", "content_format"):
            if _item_string(source, field) != _item_string(current, field):
                raise RuntimeError(f"Authoring revision manifest {field} does not match content")
        if _required_item_number(source, "revision") != revision:
            raise RuntimeError("Authoring revision manifest number does not match request")

    @staticmethod
    def _published_document_key(
        group_id: str,
        content_id: str,
        version: int,
    ) -> str:
        return f"published/{group_id}/{content_id}/versions/{version:06d}/document.json"

    @staticmethod
    def _published_asset_key(
        group_id: str,
        content_id: str,
        version: int,
        path: str,
    ) -> str:
        return f"published/{group_id}/{content_id}/versions/{version:06d}/assets/{path}"
