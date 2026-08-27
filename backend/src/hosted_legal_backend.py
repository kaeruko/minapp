from __future__ import annotations

import uuid
from typing import Any

from aws_backend import _User, _aws_error_code, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import HostedCatalogBackend
from hosted_legal import validate_legal_versions
from hosted_platform_backend import _new_recovery_code, _now_iso, _recovery_hash


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
