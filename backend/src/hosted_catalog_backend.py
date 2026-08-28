from __future__ import annotations

import hashlib
import io
import json
import secrets
import time
import uuid
import zipfile
from pathlib import PurePosixPath
from typing import Any

from aws_backend import _aws_error_code, _item_string, _required_env, _string_attr
from errors import ApiProblem
from hosted_platform_backend import (
    HostedPlatformBackend,
    MAX_RUNTIME_VALUE_BYTES,
    _now_iso,
    _number_attr,
    _runtime_token_hash,
    _validate_state_key,
)
from phase2_backend import MAX_ZIP_BYTES, _content_type, _safe_zip_paths

MAX_APPS_PER_GROUP = 20
MAX_RUNTIME_KEYS_PER_APP = 64
MAX_RUNTIME_BYTES_PER_APP = 256 * 1024
MAX_RUNTIME_REQUESTS_PER_SESSION = 300
MAX_SOURCE_REVISIONS = 20
MAX_PUBLISHED_VERSIONS = 20
HOSTED_CONTENT_SESSION_SECONDS = 10 * 60
HOSTED_CONTENT_TTL_GRACE_SECONDS = 24 * 60 * 60

BUILTIN_TEMPLATES: dict[str, dict[str, Any]] = {
    "shiba-game": {
        "builtin_id": "shiba-game",
        "version": 1,
        "title": "しば犬どんぐりキャッチ",
        "asset_path": "assets/builtin/shiba_donguri/index.html",
        "source_key": "hosted/templates/shiba-game/v1/source.zip",
    },
    "shiba-goshujin": {
        "builtin_id": "shiba-goshujin",
        "version": 1,
        "title": "ごしゅじんどこわん",
        "asset_path": "assets/builtin/shiba_goshujin/index.html",
        "source_key": "hosted/templates/shiba-goshujin/v1/source.zip",
    },
}


def _optional_number(item: dict[str, Any], key: str) -> int | None:
    raw = item.get(key)
    if raw is None:
        return None
    if not isinstance(raw, dict) or not isinstance(raw.get("N"), str):
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a number")
    try:
        return int(raw["N"])
    except ValueError as exc:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not an integer") from exc


def _optional_string(item: dict[str, Any], key: str) -> str | None:
    raw = item.get(key)
    if raw is None:
        return None
    if not isinstance(raw, dict) or not isinstance(raw.get("S"), str) or not raw["S"]:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a non-empty string")
    return raw["S"]


def _files_json(files: list[str]) -> str:
    return json.dumps(files, ensure_ascii=False, separators=(",", ":"))


def _item_files(item: dict[str, Any], key: str) -> list[str]:
    try:
        value = json.loads(_item_string(item, key))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not valid JSON") from exc
    if not isinstance(value, list) or not value or any(
        not isinstance(path, str) or not path for path in value
    ):
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a non-empty string list")
    return value


class HostedCatalogBackend(HostedPlatformBackend):
    """Hosted catalog, editable static source, publishing, and Runtime quotas."""

    def __init__(
        self,
        *,
        cognito: Any,
        dynamodb: Any,
        runtime_dynamodb: Any,
        s3: Any,
        user_pool_id: str,
        app_client_id: str,
        table_name: str,
        runtime_table_name: str,
        upload_bucket: str,
        published_bucket: str,
    ) -> None:
        super().__init__(
            cognito=cognito,
            dynamodb=dynamodb,
            runtime_dynamodb=runtime_dynamodb,
            user_pool_id=user_pool_id,
            app_client_id=app_client_id,
            table_name=table_name,
            runtime_table_name=runtime_table_name,
        )
        self._s3 = s3
        self._upload_bucket = upload_bucket
        self._published_bucket = published_bucket

    @classmethod
    def from_environment(cls) -> "HostedCatalogBackend":
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required outside the AWS Lambda runtime. Install the development requirements explicitly."
            ) from exc

        dynamodb = boto3.client("dynamodb")
        return cls(
            cognito=boto3.client("cognito-idp"),
            dynamodb=dynamodb,
            runtime_dynamodb=dynamodb,
            s3=boto3.client("s3"),
            user_pool_id=_required_env("USER_POOL_ID"),
            app_client_id=_required_env("USER_POOL_CLIENT_ID"),
            table_name=_required_env("DATA_TABLE_NAME"),
            runtime_table_name=_required_env("RUNTIME_TABLE_NAME"),
            upload_bucket=_required_env("UPLOAD_BUCKET"),
            published_bucket=_required_env("PUBLISHED_BUCKET"),
        )

    def list_builtin_templates(self) -> list[dict[str, Any]]:
        return [
            {
                field: value
                for field, value in BUILTIN_TEMPLATES[key].items()
                if field != "source_key"
            }
            for key in sorted(BUILTIN_TEMPLATES)
        ]

    def list_group_apps(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        apps = [self._public_hosted_app(item) for item in self._group_app_items(group_id)]
        apps.sort(key=lambda app: (app["title"], app["app_id"]))
        return apps

    def install_builtin(
        self,
        auth_subject: str,
        group_id: str,
        builtin_id: str,
    ) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        template = BUILTIN_TEMPLATES.get(builtin_id)
        if template is None:
            raise ApiProblem(404, "builtin_not_found", "指定されたビルトインアプリはありません。")
        self._require_app_capacity(group_id)

        for item in self._group_app_items(group_id):
            if item.get("builtin_id", {}).get("S") == builtin_id and item.get("source_kind", {}).get("S") == "builtin":
                raise ApiProblem(409, "builtin_already_installed", "このビルトインアプリはすでに入っています。")

        app_id = uuid.uuid4().hex
        created_at = _now_iso()
        common = {
            "entity": _string_attr("app"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "title": _string_attr(str(template["title"])),
            "owner_user_id": _string_attr(owner.user_id),
            "source_kind": _string_attr("builtin"),
            "builtin_id": _string_attr(builtin_id),
            "builtin_version": _number_attr(int(template["version"])),
            "builtin_asset_path": _string_attr(str(template["asset_path"])),
            "editable": {"BOOL": False},
            "created_at": _string_attr(created_at),
        }
        app_meta = {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr("META"),
            **common,
        }
        group_index = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{app_id}"),
            **common,
        }
        self._transact_put_new([app_meta, group_index])
        return self._public_hosted_app(app_meta)

    def fork_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        title: str,
    ) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        parent = self._require_app_in_group(app_id, group_id)
        self._require_not_deleting(parent)
        self._require_app_capacity(group_id)

        source_bytes, source_files, source_sha256 = self._read_parent_source(parent)

        new_app_id = uuid.uuid4().hex
        created_at = _now_iso()
        source_revision = 1
        source_key = self._draft_source_key(group_id, new_app_id, source_revision)
        common: dict[str, Any] = {
            "entity": _string_attr("app"),
            "app_id": _string_attr(new_app_id),
            "group_id": _string_attr(group_id),
            "title": _string_attr(title),
            "owner_user_id": _string_attr(owner.user_id),
            "source_kind": _string_attr("fork"),
            "parent_app_id": _string_attr(app_id),
            "editable": {"BOOL": True},
            "source_revision": _number_attr(source_revision),
            "source_key": _string_attr(source_key),
            "source_sha256": _string_attr(source_sha256),
            "source_files_json": _string_attr(_files_json(source_files)),
            "source_updated_at": _string_attr(created_at),
            "created_at": _string_attr(created_at),
        }
        builtin_id = parent.get("builtin_id", {}).get("S")
        if isinstance(builtin_id, str) and builtin_id:
            common["builtin_id"] = _string_attr(builtin_id)
        builtin_version = _optional_number(parent, "builtin_version")
        if builtin_version is not None:
            common["builtin_version"] = _number_attr(builtin_version)
        asset_path = parent.get("builtin_asset_path", {}).get("S")
        if isinstance(asset_path, str) and asset_path:
            common["builtin_asset_path"] = _string_attr(asset_path)

        app_meta = {
            "pk": _string_attr(f"APP#{new_app_id}"),
            "sk": _string_attr("META"),
            **common,
        }
        group_index = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"APP#{new_app_id}"),
            **common,
        }
        source_version_id = self._put_immutable_zip(
            bucket=self._upload_bucket,
            key=source_key,
            zip_bytes=source_bytes,
            sha256=source_sha256,
        )
        source_manifest = self._source_manifest(
            app_id=new_app_id,
            group_id=group_id,
            revision=source_revision,
            source_key=source_key,
            s3_version_id=source_version_id,
            sha256=source_sha256,
            files=source_files,
            created_at=created_at,
        )
        try:
            self._transact_put_new([app_meta, group_index, source_manifest])
        except Exception:
            self._delete_failed_write(
                self._upload_bucket, source_key, source_version_id, "Fork metadata creation"
            )
            raise
        return self._public_hosted_app(app_meta)

    def get_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
    ) -> tuple[bytes, dict[str, Any]]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_editable_app(app)
        source_bytes, files, sha256 = self._read_current_source(app)
        return source_bytes, {
            "revision": self._source_revision(app),
            "sha256": sha256,
            "files": files,
        }

    def update_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
        zip_bytes: bytes,
    ) -> dict[str, Any]:
        if not isinstance(expected_revision, int) or isinstance(expected_revision, bool) or expected_revision < 1:
            raise ApiProblem(400, "invalid_source_revision", "source revision must be a positive integer.")
        files = _safe_zip_paths(zip_bytes)
        sha256 = hashlib.sha256(zip_bytes).hexdigest()

        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_editable_app(app)
        current_revision = self._source_revision(app)
        if current_revision != expected_revision:
            raise ApiProblem(409, "source_revision_stale", "Source revision is stale; fetch the latest source first.")
        next_revision = current_revision + 1
        if next_revision > MAX_SOURCE_REVISIONS:
            raise ApiProblem(
                409,
                "source_revision_limit_reached",
                f"An app may retain at most {MAX_SOURCE_REVISIONS} source revisions.",
            )

        source_key = self._draft_source_key(group_id, app_id, next_revision)
        updated_at = _now_iso()
        try:
            source_version_id = self._put_immutable_zip(
                bucket=self._upload_bucket,
                key=source_key,
                zip_bytes=zip_bytes,
                sha256=sha256,
            )
        except FileExistsError as exc:
            raise ApiProblem(
                409,
                "source_revision_stale",
                "Source revision is stale; fetch the latest source first.",
            ) from exc

        manifest = self._source_manifest(
            app_id=app_id,
            group_id=group_id,
            revision=next_revision,
            source_key=source_key,
            s3_version_id=source_version_id,
            sha256=sha256,
            files=files,
            created_at=updated_at,
        )
        try:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._source_metadata_update(
                        pk=f"APP#{app_id}",
                        sk="META",
                        expected_revision=current_revision,
                        next_revision=next_revision,
                        source_key=source_key,
                        sha256=sha256,
                        files=files,
                        updated_at=updated_at,
                    ),
                    self._source_metadata_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        expected_revision=current_revision,
                        next_revision=next_revision,
                        source_key=source_key,
                        sha256=sha256,
                        files=files,
                        updated_at=updated_at,
                    ),
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": manifest,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                ]
            )
        except Exception as exc:
            self._delete_failed_write(
                self._upload_bucket, source_key, source_version_id, "Source metadata update"
            )
            if _aws_error_code(exc) == "TransactionCanceledException":
                raise ApiProblem(
                    409,
                    "source_revision_stale",
                    "Source revision is stale; fetch the latest source first.",
                ) from exc
            raise

        return {
            "app_id": app_id,
            "group_id": group_id,
            "revision": next_revision,
            "sha256": sha256,
            "files": files,
            "updated_at": updated_at,
        }

    def publish_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
    ) -> dict[str, Any]:
        if not isinstance(expected_revision, int) or isinstance(expected_revision, bool) or expected_revision < 1:
            raise ApiProblem(400, "invalid_source_revision", "source revision must be a positive integer.")
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_editable_app(app)
        current_revision = self._source_revision(app)
        if current_revision != expected_revision:
            raise ApiProblem(409, "source_revision_stale", "Source revision is stale; fetch the latest source first.")

        previous_version = _optional_number(app, "published_version") or 0
        published_version = previous_version + 1
        if published_version > MAX_PUBLISHED_VERSIONS:
            raise ApiProblem(
                409,
                "published_version_limit_reached",
                f"An app may retain at most {MAX_PUBLISHED_VERSIONS} published versions.",
            )
        source_bytes, files, sha256 = self._read_current_source(app)
        published_key = self._published_source_key(group_id, app_id, published_version)
        published_at = _now_iso()
        try:
            published_s3_version_id = self._put_immutable_zip(
                bucket=self._published_bucket,
                key=published_key,
                zip_bytes=source_bytes,
                sha256=sha256,
            )
        except FileExistsError as exc:
            raise ApiProblem(409, "publish_conflict", "The next published version already exists.") from exc

        manifest = self._published_manifest(
            app_id=app_id,
            group_id=group_id,
            version=published_version,
            source_revision=current_revision,
            published_key=published_key,
            s3_version_id=published_s3_version_id,
            sha256=sha256,
            files=files,
            published_at=published_at,
        )
        try:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._publish_metadata_update(
                        pk=f"APP#{app_id}",
                        sk="META",
                        expected_revision=current_revision,
                        previous_version=previous_version,
                        published_version=published_version,
                        published_key=published_key,
                        sha256=sha256,
                        files=files,
                        published_at=published_at,
                    ),
                    self._publish_metadata_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        expected_revision=current_revision,
                        previous_version=previous_version,
                        published_version=published_version,
                        published_key=published_key,
                        sha256=sha256,
                        files=files,
                        published_at=published_at,
                    ),
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": manifest,
                            "ConditionExpression": "attribute_not_exists(pk)",
                        }
                    },
                ]
            )
        except Exception as exc:
            self._delete_failed_write(
                self._published_bucket,
                published_key,
                published_s3_version_id,
                "Publish metadata update",
            )
            if _aws_error_code(exc) == "TransactionCanceledException":
                raise ApiProblem(409, "publish_conflict", "The app changed while it was being published.") from exc
            raise

        return {
            "app_id": app_id,
            "group_id": group_id,
            "published_version": published_version,
            "source_revision": current_revision,
            "sha256": sha256,
            "files": files,
            "published_at": published_at,
        }

    def create_published_session(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_not_deleting(app)
        published_version = _optional_number(app, "published_version")
        published_key = _optional_string(app, "published_key")
        published_sha256 = _optional_string(app, "published_sha256")
        if published_version is None or published_key is None or published_sha256 is None:
            raise ApiProblem(409, "app_unpublished", "This app has no published version.")
        files = _item_files(app, "published_files_json")

        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        expires_at_epoch = int(time.time()) + HOSTED_CONTENT_SESSION_SECONDS
        session = {
            "pk": _string_attr(f"HOSTEDCONTENT#{token_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("hosted_content_session"),
            "user_id": _string_attr(user.user_id),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "published_version": _number_attr(published_version),
            "published_key": _string_attr(published_key),
            "published_sha256": _string_attr(published_sha256),
            "published_files_json": _string_attr(_files_json(files)),
            "expires_at_epoch": _number_attr(expires_at_epoch),
            "ttl_epoch": _number_attr(expires_at_epoch + HOSTED_CONTENT_TTL_GRACE_SECONDS),
        }
        self._transact_put_new([session])
        return {
            "content_path": f"/hosted/content/{token}/index.html",
            "published_version": published_version,
            "expires_in": HOSTED_CONTENT_SESSION_SECONDS,
        }

    def get_published_file(self, token: str, path: str) -> tuple[bytes, str]:
        if not isinstance(token, str) or not token or len(token) > 128:
            raise ApiProblem(404, "published_content_not_found", "Published content was not found.")
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        session = self._get_item(pk=f"HOSTEDCONTENT#{token_hash}", sk="META")
        if session is None or (_optional_number(session, "expires_at_epoch") or 0) <= int(time.time()):
            raise ApiProblem(404, "published_content_not_found", "Published content was not found.")

        user_id = _item_string(session, "user_id")
        group_id = _item_string(session, "group_id")
        app_id = _item_string(session, "app_id")
        self._require_active_membership(user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_not_deleting(app)

        normalized = self._normalize_content_path(path)
        expected_files = _item_files(session, "published_files_json")
        if normalized not in expected_files:
            raise ApiProblem(404, "published_file_not_found", "Published file was not found.")
        zip_bytes, actual_files, _ = self._read_zip_object(
            bucket=self._published_bucket,
            key=_item_string(session, "published_key"),
            expected_sha256=_item_string(session, "published_sha256"),
        )
        if actual_files != expected_files:
            raise RuntimeError("Published ZIP manifest does not match DynamoDB metadata")
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
            try:
                data = archive.read(normalized)
            except KeyError as exc:
                raise ApiProblem(404, "published_file_not_found", "Published file was not found.") from exc
        return data, _content_type(normalized)

    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        self._require_app_in_group(app_id, group_id)

        deleting_at = _now_iso()
        try:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._deletion_state_update(f"APP#{app_id}", "META", deleting_at),
                    self._deletion_state_update(
                        f"GROUP#{group_id}", f"APP#{app_id}", deleting_at
                    ),
                ]
            )
        except Exception as exc:
            if _aws_error_code(exc) != "TransactionCanceledException":
                raise
            # A previous cleanup attempt may already have marked the app. The
            # manifest-driven deletes below are idempotent, so retry safely.
            app = self._require_app_in_group(app_id, group_id)
            if _optional_string(app, "deletion_state") != "deleting":
                raise

        # Once deletion_state is set, source updates and publishes cannot add
        # manifests. Querying afterward makes this exact-key cleanup race-free.
        source_manifests = self._source_manifests(app_id)
        published_manifests = self._published_manifests(app_id)
        if len(source_manifests) > MAX_SOURCE_REVISIONS:
            raise RuntimeError("Source revision count exceeds the configured deletion bound")
        if len(published_manifests) > MAX_PUBLISHED_VERSIONS:
            raise RuntimeError("Published version count exceeds the configured deletion bound")

        for manifest in source_manifests:
            self._s3.delete_object(
                Bucket=self._upload_bucket,
                Key=_item_string(manifest, "source_key"),
                VersionId=_item_string(manifest, "s3_version_id"),
            )
        for manifest in published_manifests:
            self._s3.delete_object(
                Bucket=self._published_bucket,
                Key=_item_string(manifest, "published_key"),
                VersionId=_item_string(manifest, "s3_version_id"),
            )

        runtime_items = self._runtime_items(group_id, app_id)
        if len(runtime_items) > MAX_RUNTIME_KEYS_PER_APP:
            raise RuntimeError("Runtime key count exceeds the configured deletion bound")
        if runtime_items:
            self._runtime_dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Delete": {
                            "TableName": self._runtime_table_name,
                            "Key": {"pk": item["pk"], "sk": item["sk"]},
                        }
                    }
                    for item in runtime_items
                ]
            )

        metadata_deletes = [
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"APP#{app_id}"),
                            "sk": _string_attr("META"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}"),
                            "sk": _string_attr(f"APP#{app_id}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                },
                *[
                    {
                        "Delete": {
                            "TableName": self._table_name,
                            "Key": {"pk": item["pk"], "sk": item["sk"]},
                        }
                    }
                    for item in [*source_manifests, *published_manifests]
                ],
            ]
        self._dynamodb.transact_write_items(
            TransactItems=metadata_deletes
        )

    def get_runtime_state(self, token: str, key: str) -> dict[str, Any]:
        group_id, app_id, _ = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        item = self._runtime_get_item(group_id, app_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime state was not found.")
        raw_value = _item_string(item, "value_json")
        try:
            value = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise RuntimeError("Stored runtime JSON is invalid") from exc
        return {"key": key, "value": value, "updated_at": _item_string(item, "updated_at")}

    def set_runtime_state(self, token: str, key: str, value: Any) -> dict[str, Any]:
        group_id, app_id, user_id = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        value_json = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        value_bytes = len(value_json.encode("utf-8"))
        if value_bytes > MAX_RUNTIME_VALUE_BYTES:
            raise ApiProblem(
                413,
                "runtime_value_too_large",
                f"Runtime state values must be at most {MAX_RUNTIME_VALUE_BYTES} bytes.",
            )

        items = self._runtime_items(group_id, app_id)
        existing = next((item for item in items if _item_string(item, "key") == key), None)
        if existing is None and len(items) >= MAX_RUNTIME_KEYS_PER_APP:
            raise ApiProblem(
                409,
                "runtime_key_limit_reached",
                f"1アプリが保存できるRuntimeキーは最大{MAX_RUNTIME_KEYS_PER_APP}個です。",
            )

        total_bytes = sum(self._runtime_item_bytes(item) for item in items)
        previous_bytes = 0 if existing is None else self._runtime_item_bytes(existing)
        if total_bytes - previous_bytes + value_bytes > MAX_RUNTIME_BYTES_PER_APP:
            raise ApiProblem(
                413,
                "runtime_storage_limit_reached",
                f"1アプリのRuntime保存容量は最大{MAX_RUNTIME_BYTES_PER_APP} bytesです。",
            )

        updated_at = _now_iso()
        item = {
            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
            "sk": _string_attr(f"STATE#{key}"),
            "entity": _string_attr("runtime_state"),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "key": _string_attr(key),
            "value_json": _string_attr(value_json),
            "value_bytes": _number_attr(value_bytes),
            "updated_by": _string_attr(user_id),
            "updated_at": _string_attr(updated_at),
        }
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[{"Put": {"TableName": self._runtime_table_name, "Item": item}}]
        )
        return {"key": key, "value": value, "updated_at": updated_at}

    def delete_runtime_state(self, token: str, key: str) -> None:
        group_id, app_id, _ = self._consume_runtime_request(token)
        key = _validate_state_key(key)
        item = self._runtime_get_item(group_id, app_id, key)
        if item is None:
            raise ApiProblem(404, "state_not_found", "Runtime state was not found.")
        self._runtime_dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": self._runtime_table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                            "sk": _string_attr(f"STATE#{key}"),
                        },
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
        )

    def _consume_runtime_request(self, token: str) -> tuple[str, str, str]:
        context = HostedPlatformBackend._runtime_context(self, token)
        token_hash = _runtime_token_hash(token)
        try:
            self._dynamodb.update_item(
                TableName=self._table_name,
                Key={
                    "pk": _string_attr(f"RUNTIMESESSION#{token_hash}"),
                    "sk": _string_attr("META"),
                },
                UpdateExpression="SET request_count = if_not_exists(request_count, :zero) + :one",
                ConditionExpression=(
                    "attribute_exists(pk) AND "
                    "(attribute_not_exists(request_count) OR request_count < :limit)"
                ),
                ExpressionAttributeValues={
                    ":zero": _number_attr(0),
                    ":one": _number_attr(1),
                    ":limit": _number_attr(MAX_RUNTIME_REQUESTS_PER_SESSION),
                },
            )
        except Exception as exc:
            if _aws_error_code(exc) == "ConditionalCheckFailedException":
                raise ApiProblem(
                    429,
                    "runtime_request_limit_reached",
                    "このRuntime sessionの操作上限に達しました。新しいsessionを開始してください。",
                ) from exc
            raise
        return context

    @staticmethod
    def _draft_source_key(group_id: str, app_id: str, revision: int) -> str:
        return f"hosted/drafts/{group_id}/{app_id}/revisions/{revision:06d}/source.zip"

    @staticmethod
    def _published_source_key(group_id: str, app_id: str, version: int) -> str:
        return f"hosted/published/{group_id}/{app_id}/versions/{version:06d}/source.zip"

    @staticmethod
    def _normalize_content_path(path: str) -> str:
        if not isinstance(path, str) or not path or len(path) > 512:
            raise ApiProblem(404, "published_file_not_found", "Published file was not found.")
        if "\\" in path or "\x00" in path or path.startswith("/"):
            raise ApiProblem(404, "published_file_not_found", "Published file was not found.")
        normalized = PurePosixPath(path).as_posix()
        if any(part in {"", ".", ".."} for part in normalized.split("/")):
            raise ApiProblem(404, "published_file_not_found", "Published file was not found.")
        return normalized

    @staticmethod
    def _require_not_deleting(app: dict[str, Any]) -> None:
        if _optional_string(app, "deletion_state") is not None:
            raise ApiProblem(409, "app_deleting", "This app is being deleted.")

    @classmethod
    def _require_editable_app(cls, app: dict[str, Any]) -> None:
        cls._require_not_deleting(app)
        if app.get("editable", {}).get("BOOL") is not True:
            raise ApiProblem(409, "app_not_editable", "Only forked apps have editable source.")

    @staticmethod
    def _source_revision(app: dict[str, Any]) -> int:
        revision = _optional_number(app, "source_revision")
        if revision is None or revision < 1:
            raise RuntimeError("Editable app has no valid source revision")
        return revision

    def _read_parent_source(
        self, parent: dict[str, Any]
    ) -> tuple[bytes, list[str], str]:
        source_kind = _item_string(parent, "source_kind")
        if source_kind == "builtin":
            builtin_id = _item_string(parent, "builtin_id")
            template = BUILTIN_TEMPLATES.get(builtin_id)
            if template is None or _optional_number(parent, "builtin_version") != template["version"]:
                raise RuntimeError("Installed built-in references an unsupported template version")
            return self._read_zip_object(
                bucket=self._upload_bucket,
                key=template["source_key"],
            )
        if source_kind == "fork":
            self._require_editable_app(parent)
            return self._read_current_source(parent)
        raise RuntimeError(f"Unsupported hosted app source kind: {source_kind!r}")

    def _read_current_source(
        self, app: dict[str, Any]
    ) -> tuple[bytes, list[str], str]:
        expected_files = _item_files(app, "source_files_json")
        source_bytes, actual_files, sha256 = self._read_zip_object(
            bucket=self._upload_bucket,
            key=_item_string(app, "source_key"),
            expected_sha256=_item_string(app, "source_sha256"),
        )
        if actual_files != expected_files:
            raise RuntimeError("Draft ZIP manifest does not match DynamoDB metadata")
        return source_bytes, actual_files, sha256

    def _read_zip_object(
        self,
        *,
        bucket: str,
        key: str,
        expected_sha256: str | None = None,
    ) -> tuple[bytes, list[str], str]:
        response = self._s3.get_object(Bucket=bucket, Key=key)
        body = response.get("Body")
        if body is None or not hasattr(body, "read"):
            raise RuntimeError("S3 GetObject response has no streaming body")
        data = body.read(MAX_ZIP_BYTES + 1)
        if not isinstance(data, bytes):
            raise RuntimeError("S3 GetObject body did not return bytes")
        files = _safe_zip_paths(data)
        sha256 = hashlib.sha256(data).hexdigest()
        if expected_sha256 is not None and sha256 != expected_sha256:
            raise RuntimeError("S3 ZIP checksum does not match DynamoDB metadata")
        return data, files, sha256

    def _put_immutable_zip(
        self, *, bucket: str, key: str, zip_bytes: bytes, sha256: str
    ) -> str:
        try:
            response = self._s3.put_object(
                Bucket=bucket,
                Key=key,
                Body=zip_bytes,
                ContentType="application/zip",
                Metadata={"sha256": sha256},
                IfNoneMatch="*",
            )
        except Exception as exc:
            if _aws_error_code(exc) in {"PreconditionFailed", "ConditionalRequestConflict"}:
                raise FileExistsError(key) from exc
            raise

        version_id = response.get("VersionId")
        if not isinstance(version_id, str) or not version_id:
            # Physical cleanup without ListBucketVersions depends on retaining
            # the exact version returned by the versioned Hosted bucket.
            try:
                self._s3.delete_object(Bucket=bucket, Key=key)
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Immutable source write returned no S3 VersionId and could not be cleaned up"
                ) from cleanup_exc
            raise RuntimeError("Immutable source write returned no S3 VersionId")
        return version_id

    def _delete_failed_write(
        self, bucket: str, key: str, version_id: str, operation: str
    ) -> None:
        try:
            self._s3.delete_object(Bucket=bucket, Key=key, VersionId=version_id)
        except Exception as exc:
            raise RuntimeError(
                f"{operation} failed and its uncommitted S3 object could not be removed"
            ) from exc

    def _source_manifests(self, app_id: str) -> list[dict[str, Any]]:
        return self._app_manifests(app_id, "SOURCE#")

    def _published_manifests(self, app_id: str) -> list[dict[str, Any]]:
        return self._app_manifests(app_id, "PUBLISHED#")

    def _app_manifests(self, app_id: str, prefix: str) -> list[dict[str, Any]]:
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :manifest_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"APP#{app_id}"),
                ":manifest_prefix": _string_attr(prefix),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    def _source_manifest(
        self,
        *,
        app_id: str,
        group_id: str,
        revision: int,
        source_key: str,
        s3_version_id: str,
        sha256: str,
        files: list[str],
        created_at: str,
    ) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr(f"SOURCE#{revision:06d}"),
            "entity": _string_attr("hosted_source_revision"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "source_revision": _number_attr(revision),
            "source_key": _string_attr(source_key),
            "s3_version_id": _string_attr(s3_version_id),
            "source_sha256": _string_attr(sha256),
            "source_files_json": _string_attr(_files_json(files)),
            "created_at": _string_attr(created_at),
        }

    def _published_manifest(
        self,
        *,
        app_id: str,
        group_id: str,
        version: int,
        source_revision: int,
        published_key: str,
        s3_version_id: str,
        sha256: str,
        files: list[str],
        published_at: str,
    ) -> dict[str, Any]:
        return {
            "pk": _string_attr(f"APP#{app_id}"),
            "sk": _string_attr(f"PUBLISHED#{version:06d}"),
            "entity": _string_attr("hosted_published_version"),
            "app_id": _string_attr(app_id),
            "group_id": _string_attr(group_id),
            "published_version": _number_attr(version),
            "source_revision": _number_attr(source_revision),
            "published_key": _string_attr(published_key),
            "s3_version_id": _string_attr(s3_version_id),
            "published_sha256": _string_attr(sha256),
            "published_files_json": _string_attr(_files_json(files)),
            "published_at": _string_attr(published_at),
        }

    def _source_metadata_update(
        self,
        *,
        pk: str,
        sk: str,
        expected_revision: int,
        next_revision: int,
        source_key: str,
        sha256: str,
        files: list[str],
        updated_at: str,
    ) -> dict[str, Any]:
        return {
            "Update": {
                "TableName": self._table_name,
                "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                "UpdateExpression": (
                    "SET source_revision = :next_revision, source_key = :source_key, "
                    "source_sha256 = :sha256, source_files_json = :files, "
                    "source_updated_at = :updated_at"
                ),
                "ConditionExpression": (
                    "source_revision = :expected_revision AND editable = :editable "
                    "AND attribute_not_exists(deletion_state)"
                ),
                "ExpressionAttributeValues": {
                    ":expected_revision": _number_attr(expected_revision),
                    ":next_revision": _number_attr(next_revision),
                    ":source_key": _string_attr(source_key),
                    ":sha256": _string_attr(sha256),
                    ":files": _string_attr(_files_json(files)),
                    ":updated_at": _string_attr(updated_at),
                    ":editable": {"BOOL": True},
                },
            }
        }

    def _publish_metadata_update(
        self,
        *,
        pk: str,
        sk: str,
        expected_revision: int,
        previous_version: int,
        published_version: int,
        published_key: str,
        sha256: str,
        files: list[str],
        published_at: str,
    ) -> dict[str, Any]:
        version_condition = (
            "attribute_not_exists(published_version)"
            if previous_version == 0
            else "published_version = :previous_version"
        )
        values = {
            ":expected_revision": _number_attr(expected_revision),
            ":published_version": _number_attr(published_version),
            ":published_key": _string_attr(published_key),
            ":sha256": _string_attr(sha256),
            ":files": _string_attr(_files_json(files)),
            ":published_at": _string_attr(published_at),
            ":editable": {"BOOL": True},
        }
        if previous_version:
            values[":previous_version"] = _number_attr(previous_version)
        return {
            "Update": {
                "TableName": self._table_name,
                "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                "UpdateExpression": (
                    "SET published_version = :published_version, published_key = :published_key, "
                    "published_sha256 = :sha256, published_files_json = :files, "
                    "published_at = :published_at"
                ),
                "ConditionExpression": (
                    "source_revision = :expected_revision AND editable = :editable AND "
                    f"attribute_not_exists(deletion_state) AND {version_condition}"
                ),
                "ExpressionAttributeValues": values,
            }
        }

    def _deletion_state_update(self, pk: str, sk: str, deleting_at: str) -> dict[str, Any]:
        return {
            "Update": {
                "TableName": self._table_name,
                "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                "UpdateExpression": (
                    "SET deletion_state = :deleting, deletion_started_at = :deleting_at"
                ),
                "ConditionExpression": (
                    "attribute_exists(pk) AND attribute_not_exists(deletion_state)"
                ),
                "ExpressionAttributeValues": {
                    ":deleting": _string_attr("deleting"),
                    ":deleting_at": _string_attr(deleting_at),
                },
            }
        }

    def _require_app_capacity(self, group_id: str) -> None:
        if len(self._group_app_items(group_id)) >= MAX_APPS_PER_GROUP:
            raise ApiProblem(
                409,
                "app_limit_reached",
                f"1グループに置けるアプリは最大{MAX_APPS_PER_GROUP}個です。",
            )

    def _runtime_items(self, group_id: str, app_id: str) -> list[dict[str, Any]]:
        response = self._runtime_dynamodb.query(
            TableName=self._runtime_table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :state_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}#APP#{app_id}"),
                ":state_prefix": _string_attr("STATE#"),
            },
            ConsistentRead=True,
        )
        return self._query_items(response)

    @staticmethod
    def _runtime_item_bytes(item: dict[str, Any]) -> int:
        stored = _optional_number(item, "value_bytes")
        if stored is not None:
            return stored
        return len(_item_string(item, "value_json").encode("utf-8"))

    @staticmethod
    def _public_hosted_app(item: dict[str, Any]) -> dict[str, Any]:
        result: dict[str, Any] = {
            "app_id": _item_string(item, "app_id"),
            "group_id": _item_string(item, "group_id"),
            "title": _item_string(item, "title"),
            "source_kind": _item_string(item, "source_kind"),
            "created_at": _item_string(item, "created_at"),
        }
        for field in (
            "builtin_id",
            "builtin_asset_path",
            "parent_app_id",
            "source_sha256",
            "source_updated_at",
            "published_sha256",
            "published_at",
            "deletion_state",
        ):
            value = item.get(field, {}).get("S")
            if isinstance(value, str) and value:
                result[field] = value
        builtin_version = _optional_number(item, "builtin_version")
        if builtin_version is not None:
            result["builtin_version"] = builtin_version
        for field in ("source_revision", "published_version"):
            number = _optional_number(item, field)
            if number is not None:
                result[field] = number
        editable = item.get("editable", {}).get("BOOL")
        if isinstance(editable, bool):
            result["editable"] = editable
        return result
