from __future__ import annotations

import hashlib
import io
import json
import uuid
import zipfile
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_app_source import resolve_authoring_app_source
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
from hosted_authoring_preview import _compile_index_html, _require_player_support
from hosted_catalog_backend import (
    _files_json,
    _item_files,
    _optional_number,
    _optional_string,
)
from hosted_platform_backend import _now_iso, _number_attr
from phase2_backend import MAX_ZIP_BYTES, _safe_zip_paths

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
    """Publish immutable Authoring revisions as ordinary Hosted app artifacts."""

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

        player_selection = self._selected_player(current)
        artifact_bytes, artifact_files = self._materialize_app_artifact(
            document=document,
            assets=asset_bytes,
            selection=player_selection,
        )
        artifact_sha256 = hashlib.sha256(artifact_bytes).hexdigest()

        group_id = _item_string(current, "group_id")
        content_format = _item_string(current, "content_format")
        owner_user_id = _item_string(current, "owner_user_id")
        published_app_id = _optional_string(current, "published_app_id")
        first_publish = published_app_id is None
        if first_publish:
            self._require_app_capacity(group_id)
            published_app_id = uuid.uuid4().hex
        assert published_app_id is not None

        written: list[tuple[str, str]] = []
        try:
            # Keep the immutable Authoring publication materialization for
            # revision history while also producing the normal app ZIP boundary.
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

            artifact_key = self._published_source_key(
                group_id,
                published_app_id,
                next_version,
            )
            artifact_s3_version_id = self._put_immutable_zip(
                bucket=self._published_bucket,
                key=artifact_key,
                zip_bytes=artifact_bytes,
                sha256=artifact_sha256,
            )
            written.append((artifact_key, artifact_s3_version_id))

            # Read the finished ZIP through the same primitive used by Runtime
            # before any pointer becomes visible.
            verified_zip, verified_files, verified_sha256 = self._read_zip_object(
                bucket=self._published_bucket,
                key=artifact_key,
                expected_sha256=artifact_sha256,
            )
            if (
                verified_zip != artifact_bytes
                or verified_files != artifact_files
                or verified_sha256 != artifact_sha256
            ):
                raise RuntimeError("Published Authoring app artifact changed during verification")

            published_at = _now_iso()
            authoring_manifest = {
                "pk": _string_attr(f"CONTENT#{content_id}"),
                "sk": _string_attr(f"PUBLISHED#{next_version:06d}"),
                "entity": _string_attr("authoring_published_version"),
                "content_id": _string_attr(content_id),
                "group_id": _string_attr(group_id),
                "owner_user_id": _string_attr(owner_user_id),
                "content_format": _string_attr(content_format),
                "published_version": _number_attr(next_version),
                "source_revision": _number_attr(expected_revision),
                "document_key": _string_attr(document_key),
                "document_sha256": _string_attr(document_sha256),
                "document_bytes": _number_attr(len(document_bytes)),
                "assets_json": _string_attr(_assets_json(published_assets)),
                "published_app_id": _string_attr(published_app_id),
                "player_app_id": _string_attr(player_selection["player_app_id"]),
                "player_source_version": _number_attr(player_selection["player_source_version"]),
                "artifact_key": _string_attr(artifact_key),
                "artifact_sha256": _string_attr(artifact_sha256),
                "artifact_files_json": _string_attr(_files_json(artifact_files)),
                "published_at": _string_attr(published_at),
            }
            app_manifest = self._published_manifest(
                app_id=published_app_id,
                group_id=group_id,
                version=next_version,
                source_revision=expected_revision,
                published_key=artifact_key,
                s3_version_id=artifact_s3_version_id,
                sha256=artifact_sha256,
                files=artifact_files,
                published_at=published_at,
            )
            self._commit_publish_pointer(
                current=current,
                content_id=content_id,
                expected_revision=expected_revision,
                previous_version=previous_version,
                next_version=next_version,
                published_app_id=published_app_id,
                published_at=published_at,
                player_selection=player_selection,
                artifact_key=artifact_key,
                artifact_sha256=artifact_sha256,
                artifact_files=artifact_files,
                authoring_manifest=authoring_manifest,
                app_manifest=app_manifest,
                first_publish=first_publish,
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
            "published_app_id": published_app_id,
            "player_app_id": player_selection["player_app_id"],
            "player_source_version": player_selection["player_source_version"],
            "assets": _public_assets(published_assets),
            "published_at": published_at,
        }

    def _selected_player(self, current: dict[str, Any]) -> dict[str, Any]:
        content_id = _item_string(current, "content_id")
        selection = self._get_item(pk=f"CONTENT#{content_id}", sk="PLAYER")
        if selection is None:
            raise ApiProblem(
                409,
                "authoring_player_not_selected",
                "Preview this project with a compatible Player before publishing.",
            )
        if _item_string(selection, "entity") != "authoring_player_selection":
            raise RuntimeError("Authoring Player selection has an unexpected entity")
        for field in ("content_id", "group_id", "content_format"):
            if _item_string(selection, field) != _item_string(current, field):
                raise RuntimeError(f"Authoring Player selection scope mismatch: {field}")
        if _item_string(selection, "user_id") != _item_string(current, "owner_user_id"):
            raise RuntimeError("Authoring Player selection owner no longer matches content")

        player_app_id = _item_string(selection, "player_app_id")
        player = self._require_app_in_group(
            player_app_id,
            _item_string(current, "group_id"),
        )
        self._require_not_deleting(player)
        _require_player_support(player, _item_string(current, "content_format"))
        current_source = resolve_authoring_app_source(
            self,
            player,
            require_master_data_target=True,
        )
        selected_target = _item_string(selection, "master_data_element_id")
        if current_source.master_data_element_id != selected_target:
            raise ApiProblem(
                409,
                "authoring_player_selection_changed",
                "The selected Player contract changed; preview again before publishing.",
            )

        source_bucket = _item_string(selection, "player_source_bucket")
        if source_bucket not in {self._upload_bucket, self._published_bucket}:
            raise RuntimeError("Authoring Player selection contains an unexpected source bucket")
        source_key = _item_string(selection, "player_source_key")
        source_sha256 = _item_string(selection, "player_source_sha256")
        source_files = _item_files(selection, "player_source_files_json")
        _, actual_files, actual_sha256 = self._read_zip_object(
            bucket=source_bucket,
            key=source_key,
            expected_sha256=source_sha256,
        )
        if actual_files != source_files or actual_sha256 != source_sha256:
            raise RuntimeError("Selected immutable Player source no longer matches metadata")
        return {
            "player_app_id": player_app_id,
            "player_source_bucket": source_bucket,
            "player_source_key": source_key,
            "player_source_sha256": source_sha256,
            "player_source_files": source_files,
            "player_source_version": _required_item_number(
                selection,
                "player_source_version",
            ),
            "master_data_element_id": selected_target,
        }

    def _materialize_app_artifact(
        self,
        *,
        document: dict[str, Any],
        assets: dict[str, bytes],
        selection: dict[str, Any],
    ) -> tuple[bytes, list[str]]:
        source_files = list(selection["player_source_files"])
        collisions = sorted(set(source_files).intersection(assets))
        if collisions:
            raise ApiProblem(
                409,
                "authoring_publish_asset_collision",
                f"Authoring asset path collides with Player source: {collisions[0]}",
            )
        source_zip, actual_files, actual_sha256 = self._read_zip_object(
            bucket=str(selection["player_source_bucket"]),
            key=str(selection["player_source_key"]),
            expected_sha256=str(selection["player_source_sha256"]),
        )
        if actual_files != source_files or actual_sha256 != selection["player_source_sha256"]:
            raise RuntimeError("Selected Player source changed during Authoring publish")

        output = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(source_zip)) as source_archive, zipfile.ZipFile(
            output,
            "w",
            compression=zipfile.ZIP_DEFLATED,
        ) as target_archive:
            for path in sorted(source_files):
                try:
                    data = source_archive.read(path)
                except KeyError as exc:
                    raise RuntimeError("Selected Player ZIP manifest is inconsistent") from exc
                if path == "index.html":
                    data = _compile_index_html(
                        data,
                        document,
                        str(selection["master_data_element_id"]),
                    )
                self._write_deterministic_zip_entry(target_archive, path, data)
            for path in sorted(assets):
                self._write_deterministic_zip_entry(target_archive, path, assets[path])

        artifact = output.getvalue()
        if len(artifact) > MAX_ZIP_BYTES:
            raise ApiProblem(
                413,
                "authoring_published_app_too_large",
                f"Published Authoring app ZIP must be at most {MAX_ZIP_BYTES} bytes.",
            )
        files = _safe_zip_paths(artifact)
        return artifact, files

    @staticmethod
    def _write_deterministic_zip_entry(
        archive: zipfile.ZipFile,
        path: str,
        data: bytes,
    ) -> None:
        info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, data)

    def _commit_publish_pointer(
        self,
        *,
        current: dict[str, Any],
        content_id: str,
        expected_revision: int,
        previous_version: int,
        next_version: int,
        published_app_id: str,
        published_at: str,
        player_selection: dict[str, Any],
        artifact_key: str,
        artifact_sha256: str,
        artifact_files: list[str],
        authoring_manifest: dict[str, Any],
        app_manifest: dict[str, Any],
        first_publish: bool,
    ) -> None:
        values = {
            ":expected_revision": _number_attr(expected_revision),
            ":next_version": _number_attr(next_version),
            ":published_revision": _number_attr(expected_revision),
            ":published_at": _string_attr(published_at),
            ":published_app_id": _string_attr(published_app_id),
            ":player_app_id": _string_attr(str(player_selection["player_app_id"])),
            ":player_source_version": _number_attr(int(player_selection["player_source_version"])),
        }
        if previous_version == 0:
            pointer_condition = "attribute_not_exists(published_version)"
        else:
            pointer_condition = "published_version = :previous_version"
            values[":previous_version"] = _number_attr(previous_version)

        operations: list[dict[str, Any]] = [
            {
                "Put": {
                    "TableName": self._table_name,
                    "Item": authoring_manifest,
                    "ConditionExpression": "attribute_not_exists(pk)",
                }
            },
            {
                "Put": {
                    "TableName": self._table_name,
                    "Item": app_manifest,
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
                        "published_app_id = :published_app_id, "
                        "published_player_app_id = :player_app_id, "
                        "published_player_source_version = :player_source_version, "
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

        if first_publish:
            created_at = _item_string(current, "created_at")
            common = {
                "entity": _string_attr("app"),
                "app_id": _string_attr(published_app_id),
                "group_id": _string_attr(_item_string(current, "group_id")),
                "title": _string_attr(f"作品 {content_id[:8]}"),
                "owner_user_id": _string_attr(_item_string(current, "owner_user_id")),
                "source_kind": _string_attr("authoring"),
                "editable": {"BOOL": False},
                "authoring_content_id": _string_attr(content_id),
                "authoring_content_format": _string_attr(_item_string(current, "content_format")),
                "published_version": _number_attr(next_version),
                "published_key": _string_attr(artifact_key),
                "published_sha256": _string_attr(artifact_sha256),
                "published_files_json": _string_attr(_files_json(artifact_files)),
                "published_at": _string_attr(published_at),
                "created_at": _string_attr(created_at),
            }
            app_meta = {
                "pk": _string_attr(f"APP#{published_app_id}"),
                "sk": _string_attr("META"),
                **common,
            }
            group_index = {
                "pk": _string_attr(f"GROUP#{_item_string(current, 'group_id')}"),
                "sk": _string_attr(f"APP#{published_app_id}"),
                **common,
            }
            operations.extend(
                [
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": app_meta,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": group_index,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                ]
            )
        else:
            app_meta = self._get_item(pk=f"APP#{published_app_id}", sk="META")
            group_index = self._get_item(
                pk=f"GROUP#{_item_string(current, 'group_id')}",
                sk=f"APP#{published_app_id}",
            )
            if app_meta is None or group_index is None:
                raise RuntimeError("Published Authoring app metadata is missing")
            for item in (app_meta, group_index):
                if _item_string(item, "authoring_content_id") != content_id:
                    raise RuntimeError("Published app no longer belongs to this Authoring content")
                if _optional_number(item, "published_version") != previous_version:
                    raise RuntimeError("Published app version no longer matches Authoring content")
                replacement = dict(item)
                replacement.update(
                    {
                        "published_version": _number_attr(next_version),
                        "published_key": _string_attr(artifact_key),
                        "published_sha256": _string_attr(artifact_sha256),
                        "published_files_json": _string_attr(_files_json(artifact_files)),
                        "published_at": _string_attr(published_at),
                    }
                )
                operations.append(
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": replacement,
                            "ConditionExpression": (
                                "authoring_content_id = :content_id AND "
                                "published_version = :previous_version"
                            ),
                            "ExpressionAttributeValues": {
                                ":content_id": _string_attr(content_id),
                                ":previous_version": _number_attr(previous_version),
                            },
                        }
                    }
                )

        try:
            self._dynamodb.transact_write_items(TransactItems=operations)
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