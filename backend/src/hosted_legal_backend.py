from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
import hashlib
import json
import secrets
import time
import uuid
from typing import Any, Iterator

from aws_backend import _User, _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_builtin_registry import merged_builtin_templates
from hosted_catalog_backend import (
    BUILTIN_TEMPLATES,
    HOSTED_CONTENT_SESSION_SECONDS,
    HOSTED_CONTENT_TTL_GRACE_SECONDS,
    HostedCatalogBackend,
    _files_json,
    _item_files,
    _optional_number,
    _optional_string,
)
from hosted_legal import validate_legal_versions
from hosted_platform_backend import (
    RUNTIME_SESSION_TTL_SECONDS,
    _new_recovery_code,
    _now_iso,
    _number_attr,
    _recovery_hash,
)

_APP_OWNER_GROUP_OVERRIDE: ContextVar[tuple[str, str] | None] = ContextVar(
    "hosted_app_owner_group_override",
    default=None,
)


class HostedLegalBackend(HostedCatalogBackend):
    """Hosted catalog backend with auditable registration consent records."""

    @staticmethod
    def _hosted_builtin_templates() -> dict[str, dict[str, Any]]:
        return merged_builtin_templates(BUILTIN_TEMPLATES)

    def list_builtin_templates(self) -> list[dict[str, Any]]:
        templates = self._hosted_builtin_templates()
        private_fields = {"source_key", "accepts", "edits"}
        return [
            {
                field: value
                for field, value in templates[builtin_id].items()
                if field not in private_fields
            }
            for builtin_id in sorted(templates)
        ]

    def _require_owner_group(self, user_id: str, group_id: str) -> dict[str, Any]:
        if _APP_OWNER_GROUP_OVERRIDE.get() == (user_id, group_id):
            return self._require_active_membership(user_id, group_id)
        return super()._require_owner_group(user_id, group_id)

    @contextmanager
    def _allow_owned_app_group(self, user_id: str, group_id: str) -> Iterator[None]:
        token = _APP_OWNER_GROUP_OVERRIDE.set((user_id, group_id))
        try:
            yield
        finally:
            _APP_OWNER_GROUP_OVERRIDE.reset(token)

    def _require_owned_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        *,
        editable: bool,
    ) -> tuple[_User, dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        app = self._require_app_in_group(app_id, group_id)
        self._require_not_deleting(app)
        if _item_string(app, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "このアプリを管理する権限がありません。")
        if editable:
            self._require_editable_app(app)
        return user, app

    def fork_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        title: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        parent = self._require_app_in_group(app_id, group_id)
        self._require_not_deleting(parent)
        with self._allow_owned_app_group(user.user_id, group_id):
            return super().fork_app(auth_subject, group_id, app_id, title)

    def get_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
    ) -> tuple[bytes, dict[str, Any]]:
        user, _ = self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
        with self._allow_owned_app_group(user.user_id, group_id):
            return super().get_editable_source(auth_subject, group_id, app_id)

    def update_editable_source(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
        zip_bytes: bytes,
    ) -> dict[str, Any]:
        user, _ = self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
        with self._allow_owned_app_group(user.user_id, group_id):
            return super().update_editable_source(
                auth_subject,
                group_id,
                app_id,
                expected_revision,
                zip_bytes,
            )

    def publish_app(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        expected_revision: int,
    ) -> dict[str, Any]:
        user, _ = self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
        with self._allow_owned_app_group(user.user_id, group_id):
            return super().publish_app(
                auth_subject,
                group_id,
                app_id,
                expected_revision,
            )

    def delete_hosted_app(self, auth_subject: str, group_id: str, app_id: str) -> None:
        user, _ = self._require_owned_app(
            auth_subject,
            group_id,
            app_id,
            editable=False,
        )
        with self._allow_owned_app_group(user.user_id, group_id):
            super().delete_hosted_app(auth_subject, group_id, app_id)

    def install_builtin(
        self,
        auth_subject: str,
        group_id: str,
        builtin_id: str,
    ) -> dict[str, Any]:
        owner = self._user_by_auth_subject(auth_subject)
        self._require_owner_group(owner.user_id, group_id)
        template = self._hosted_builtin_templates().get(builtin_id)
        if template is None:
            raise ApiProblem(404, "builtin_not_found", "指定されたビルトインアプリはありません。")
        self._require_app_capacity(group_id)

        for item in self._group_app_items(group_id):
            if (
                item.get("builtin_id", {}).get("S") == builtin_id
                and item.get("source_kind", {}).get("S") == "builtin"
            ):
                raise ApiProblem(
                    409,
                    "builtin_already_installed",
                    "このビルトインアプリはすでに入っています。",
                )

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
        for contract_field in ("accepts", "edits"):
            formats = template.get(contract_field)
            if formats is not None:
                common[f"{contract_field}_json"] = _string_attr(
                    json.dumps(formats, separators=(",", ":"))
                )
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

    def _read_parent_source(
        self, parent: dict[str, Any]
    ) -> tuple[bytes, list[str], str]:
        if _item_string(parent, "source_kind") != "builtin":
            return super()._read_parent_source(parent)

        builtin_id = _item_string(parent, "builtin_id")
        template = self._hosted_builtin_templates().get(builtin_id)
        if (
            template is None
            or _optional_number(parent, "builtin_version") != template["version"]
        ):
            raise RuntimeError(
                "Installed built-in references an unsupported template version"
            )
        return self._read_zip_object(
            bucket=self._upload_bucket,
            key=str(template["source_key"]),
        )

    def register(
        self,
        login_id: str,
        password: str,
        terms_version: str,
        privacy_version: str,
    ) -> dict[str, Any]:
        validate_legal_versions(terms_version, privacy_version)

        user_id = uuid.uuid4().hex
        recovery_code = _new_recovery_code()
        recovery_hash = _recovery_hash(recovery_code)
        accepted_at = _now_iso()

        try:
            self._cognito.admin_create_user(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                TemporaryPassword=password,
                MessageAction="SUPPRESS",
            )
        except Exception as exc:
            code = _aws_error_code(exc)
            if code == "UsernameExistsException":
                raise ApiProblem(409, "login_id_conflict", "このIDはすでに使われています。") from exc
            if code == "InvalidPasswordException":
                raise ApiProblem(400, "invalid_password", "パスワードがポリシーを満たしていません。") from exc
            raise

        try:
            self._cognito.admin_set_user_password(
                UserPoolId=self._user_pool_id,
                Username=login_id,
                Password=password,
                Permanent=True,
            )
            auth_subject = self._cognito_subject(login_id)
            user = _User(
                user_id=user_id,
                auth_subject=auth_subject,
                login_id=login_id,
                role="user",
                status="active",
            )
            auth_item = self._auth_item(user)
            user_item = self._user_item(user)
            for item in (auth_item, user_item):
                item["recovery_hash"] = _string_attr(recovery_hash)
                item["terms_version"] = _string_attr(terms_version)
                item["privacy_version"] = _string_attr(privacy_version)
                item["terms_accepted"] = {"BOOL": True}
                item["privacy_accepted"] = {"BOOL": True}
                item["terms_accepted_at"] = _string_attr(accepted_at)
                item["privacy_accepted_at"] = _string_attr(accepted_at)
            self._transact_put_new([auth_item, user_item])
        except Exception as original_exc:
            try:
                self._cognito.admin_delete_user(
                    UserPoolId=self._user_pool_id,
                    Username=login_id,
                )
            except Exception as cleanup_exc:
                raise RuntimeError(
                    "Hosted registration failed after Cognito user creation, and cleanup also failed."
                ) from cleanup_exc
            raise original_exc

        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "status": user.status,
            "recovery_code": recovery_code,
            "legal": {
                "terms_version": terms_version,
                "privacy_version": privacy_version,
                "accepted_at": accepted_at,
            },
        }

    def create_launch_session(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
    ) -> dict[str, Any]:
        """Atomically mint content and Runtime capabilities for one Hosted app launch."""

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

        content_token = secrets.token_urlsafe(32)
        runtime_token = secrets.token_urlsafe(32)
        content_token_hash = hashlib.sha256(content_token.encode("ascii")).hexdigest()
        runtime_token_hash = hashlib.sha256(runtime_token.encode("ascii")).hexdigest()
        now_epoch = int(time.time())
        content_expires_at = now_epoch + HOSTED_CONTENT_SESSION_SECONDS
        runtime_expires_at = now_epoch + RUNTIME_SESSION_TTL_SECONDS

        content_session = {
            "pk": _string_attr(f"HOSTEDCONTENT#{content_token_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("hosted_content_session"),
            "user_id": _string_attr(user.user_id),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "published_version": _number_attr(published_version),
            "published_key": _string_attr(published_key),
            "published_sha256": _string_attr(published_sha256),
            "published_files_json": _string_attr(_files_json(files)),
            "expires_at_epoch": _number_attr(content_expires_at),
            "ttl_epoch": _number_attr(
                content_expires_at + HOSTED_CONTENT_TTL_GRACE_SECONDS
            ),
        }
        runtime_session = {
            "pk": _string_attr(f"RUNTIMESESSION#{runtime_token_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("runtime_session"),
            "group_id": _string_attr(group_id),
            "app_id": _string_attr(app_id),
            "user_id": _string_attr(user.user_id),
            "expires_at_epoch": _number_attr(runtime_expires_at),
            "ttl_epoch": _number_attr(runtime_expires_at + 24 * 60 * 60),
        }

        # Both capability rows live in the metadata table, so a single DynamoDB
        # transaction gives all-or-nothing launch creation. There is no partial
        # session to clean up if the write fails.
        self._transact_put_new([content_session, runtime_session])

        return {
            "content_path": f"/hosted/content/{content_token}/index.html",
            "content_expires_in": HOSTED_CONTENT_SESSION_SECONDS,
            "runtime_token": runtime_token,
            "runtime_expires_in": RUNTIME_SESSION_TTL_SECONDS,
            "published_version": published_version,
        }
