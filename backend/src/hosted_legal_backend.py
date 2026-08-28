from __future__ import annotations

import hashlib
import secrets
import time
import uuid
from typing import Any

from aws_backend import _User, _aws_error_code, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import (
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


class HostedLegalBackend(HostedCatalogBackend):
    """Hosted catalog backend with auditable registration consent records."""

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
            "ttl_epoch": _number_attr(content_expires_at + HOSTED_CONTENT_TTL_GRACE_SECONDS),
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
