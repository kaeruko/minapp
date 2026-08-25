from __future__ import annotations

import copy
import re
from typing import Any

from aws_backend import (
    _aws_error_code,
    _item_string,
    _new_temporary_password,
    _string_attr,
)
from errors import ApiProblem
from phase2_backend import _optional_item_string
from phase4_moderation_backend import Phase4ModerationAwsBackend

_LOGIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,31}$")
_MAX_LOGIN_ID_TRANSACTION_ITEMS = 100


class DisplayNameAwsBackend(Phase4ModerationAwsBackend):
    """Optional display names and teacher-managed student login IDs."""

    def _display_name(self, user_id: str) -> str | None:
        item = self._get_item(pk=f"USER#{user_id}", sk="DISPLAY_NAME")
        if item is None:
            return None
        if _item_string(item, "entity") != "user_display_name":
            raise RuntimeError("Display-name item has an unexpected entity type")
        name = _optional_item_string(item, "display_name")
        if name is None:
            raise RuntimeError("Display-name item has no display_name")
        if name != name.strip() or len(name) < 1 or len(name) > 40:
            raise RuntimeError("Stored display_name is invalid")
        return name

    def _write_display_name(self, user_id: str, display_name: str) -> None:
        if not isinstance(display_name, str):
            raise TypeError("display_name must be a string")
        if display_name != display_name.strip() or len(display_name) < 1 or len(display_name) > 40:
            raise ValueError("display_name must be 1-40 characters without surrounding whitespace")
        if any(ord(char) < 0x20 or ord(char) == 0x7F for char in display_name):
            raise ValueError("display_name must not contain control characters")
        self._dynamodb.put_item(
            TableName=self._table_name,
            Item={
                "pk": _string_attr(f"USER#{user_id}"),
                "sk": _string_attr("DISPLAY_NAME"),
                "entity": _string_attr("user_display_name"),
                "user_id": _string_attr(user_id),
                "display_name": _string_attr(display_name),
            },
            ConditionExpression="attribute_not_exists(pk) OR user_id = :user_id",
            ExpressionAttributeValues={":user_id": _string_attr(user_id)},
        )

    def get_my_display_name(self, auth_subject: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "display_name": self._display_name(user.user_id),
        }

    def set_my_display_name(self, auth_subject: str, display_name: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        self._write_display_name(user.user_id, display_name)
        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "display_name": display_name,
        }

    def set_user_display_name(
        self,
        auth_subject: str,
        user_id: str,
        display_name: str,
    ) -> dict[str, Any]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_role(teacher, "teacher")
        target = self._user_by_id(user_id)
        if target.user_id == teacher.user_id:
            raise ApiProblem(400, "invalid_request", "自分の名前は設定画面から変更してください。")
        self._require_role(target, "student")
        self._require_shared_teacher_group(teacher.user_id, target.user_id)
        self._write_display_name(target.user_id, display_name)
        return {
            "user_id": target.user_id,
            "login_id": target.login_id,
            "role": target.role,
            "display_name": display_name,
        }

    def list_group_display_names(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        teacher = self._user_by_auth_subject(auth_subject)
        self._require_teacher_membership(teacher.user_id, group_id)
        members = super().list_members(auth_subject, group_id)
        result: list[dict[str, Any]] = []
        for member in members:
            user_id = member.get("user_id")
            if not isinstance(user_id, str) or not user_id:
                raise RuntimeError("Member user_id is invalid")
            enriched = dict(member)
            enriched["display_name"] = self._display_name(user_id)
            result.append(enriched)
        return result

    def change_student_login_id(
        self,
        auth_subject: str,
        user_id: str,
        new_login_id: str,
    ) -> dict[str, Any]:
        if not isinstance(new_login_id, str):
            raise TypeError("new_login_id must be a string")
        if _LOGIN_ID_RE.fullmatch(new_login_id) is None:
            raise ValueError("new_login_id must be a valid login ID")

        teacher = self._user_by_auth_subject(auth_subject)
        self._require_role(teacher, "teacher")
        target = self._user_by_id(user_id)
        self._require_role(target, "student")
        self._require_shared_teacher_group(teacher.user_id, target.user_id)

        old_login_id = target.login_id
        old_subject = target.auth_subject
        if new_login_id == old_login_id:
            raise ApiProblem(400, "invalid_request", "新しいIDは現在のIDと異なるものを指定してください。")

        actual_old_subject = self._cognito_subject(old_login_id)
        if actual_old_subject != old_subject:
            raise RuntimeError("Cognito subject and DynamoDB user profile do not match")
        self._ensure_cognito_login_absent(new_login_id)

        items = self._scan_all_items()
        user_profiles = [
            item
            for item in items
            if item.get("pk") == _string_attr(f"USER#{target.user_id}")
            and item.get("sk") == _string_attr("PROFILE")
            and item.get("entity") == _string_attr("user")
        ]
        if len(user_profiles) != 1:
            raise RuntimeError(
                f"Expected exactly one user profile for user_id={target.user_id!r}, found {len(user_profiles)}"
            )
        user_profile = user_profiles[0]
        if _item_string(user_profile, "login_id") != old_login_id:
            raise RuntimeError("Stored user profile login ID changed during migration planning")
        if _item_string(user_profile, "auth_subject") != old_subject:
            raise RuntimeError("Stored user profile auth subject changed during migration planning")

        affected_originals = [
            copy.deepcopy(item)
            for item in items
            if (
                item.get("login_id") == _string_attr(old_login_id)
                or item.get("owner_login_id") == _string_attr(old_login_id)
                or item.get("auth_subject") == _string_attr(old_subject)
                or (
                    item.get("pk") == _string_attr(f"AUTH#{old_subject}")
                    and item.get("sk") == _string_attr("PROFILE")
                )
            )
        ]
        if not affected_originals:
            raise RuntimeError("No DynamoDB records reference the student's current login ID")
        if len(affected_originals) + 1 > _MAX_LOGIN_ID_TRANSACTION_ITEMS:
            raise RuntimeError(
                "Login ID change touches too many DynamoDB records for one atomic transaction; no changes were made."
            )

        temporary_password = _new_temporary_password()
        try:
            self._cognito.admin_create_user(
                UserPoolId=self._user_pool_id,
                Username=new_login_id,
                TemporaryPassword=temporary_password,
                MessageAction="SUPPRESS",
            )
        except Exception as exc:
            if _aws_error_code(exc) == "UsernameExistsException":
                raise ApiProblem(409, "login_id_conflict", "指定したIDはすでに使われています。別のIDを入力してください。") from exc
            raise

        dynamodb_changed = False
        new_auth_item: dict[str, Any] | None = None
        try:
            new_subject = self._cognito_subject(new_login_id)
            if new_subject == old_subject:
                raise RuntimeError("New Cognito user unexpectedly reused the old subject")

            changed, old_auth_item, new_auth_item = self._replacement_login_items(
                items,
                old_login_id=old_login_id,
                new_login_id=new_login_id,
                old_subject=old_subject,
                new_subject=new_subject,
            )
            operations = [
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {"pk": old_auth_item["pk"], "sk": old_auth_item["sk"]},
                        "ConditionExpression": "attribute_exists(pk)",
                    }
                }
            ]
            operations.extend(
                {"Put": {"TableName": self._table_name, "Item": item}}
                for item in changed
            )
            if len(operations) > _MAX_LOGIN_ID_TRANSACTION_ITEMS:
                raise RuntimeError("Login ID transaction unexpectedly exceeds the fail-fast limit")
            self._dynamodb.transact_write_items(TransactItems=operations)
            dynamodb_changed = True

            self._cognito.admin_delete_user(
                UserPoolId=self._user_pool_id,
                Username=old_login_id,
            )
        except Exception as original_exc:
            rollback_errors: list[str] = []
            if dynamodb_changed:
                if new_auth_item is None:
                    rollback_errors.append("new auth item was unavailable for DynamoDB rollback")
                else:
                    try:
                        rollback_operations = [
                            {
                                "Delete": {
                                    "TableName": self._table_name,
                                    "Key": {"pk": new_auth_item["pk"], "sk": new_auth_item["sk"]},
                                }
                            }
                        ]
                        rollback_operations.extend(
                            {"Put": {"TableName": self._table_name, "Item": item}}
                            for item in affected_originals
                        )
                        if len(rollback_operations) > _MAX_LOGIN_ID_TRANSACTION_ITEMS:
                            raise RuntimeError("Rollback transaction unexpectedly exceeds the fail-fast limit")
                        self._dynamodb.transact_write_items(TransactItems=rollback_operations)
                    except Exception as rollback_exc:
                        rollback_errors.append(f"DynamoDB rollback failed: {rollback_exc!r}")
            try:
                self._cognito.admin_delete_user(
                    UserPoolId=self._user_pool_id,
                    Username=new_login_id,
                )
            except Exception as cleanup_exc:
                rollback_errors.append(f"new Cognito user cleanup failed: {cleanup_exc!r}")
            if rollback_errors:
                raise RuntimeError(
                    "Login ID change failed and rollback was incomplete: " + "; ".join(rollback_errors)
                ) from original_exc
            raise

        return {
            "user_id": target.user_id,
            "old_login_id": old_login_id,
            "login_id": new_login_id,
            "role": target.role,
            "display_name": self._display_name(target.user_id),
            "temporary_password": temporary_password,
        }

    def _ensure_cognito_login_absent(self, login_id: str) -> None:
        try:
            self._cognito.admin_get_user(
                UserPoolId=self._user_pool_id,
                Username=login_id,
            )
        except Exception as exc:
            if _aws_error_code(exc) == "UserNotFoundException":
                return
            raise
        raise ApiProblem(409, "login_id_conflict", "指定したIDはすでに使われています。別のIDを入力してください。")

    def _scan_all_items(self) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        request: dict[str, Any] = {
            "TableName": self._table_name,
            "ConsistentRead": True,
        }
        while True:
            response = self._dynamodb.scan(**request)
            page = response.get("Items")
            if not isinstance(page, list) or any(not isinstance(item, dict) for item in page):
                raise RuntimeError("DynamoDB Scan response has an invalid Items list")
            items.extend(page)
            last_key = response.get("LastEvaluatedKey")
            if last_key is None:
                return items
            if not isinstance(last_key, dict) or not last_key:
                raise RuntimeError("DynamoDB Scan returned an invalid LastEvaluatedKey")
            request["ExclusiveStartKey"] = last_key

    @staticmethod
    def _replacement_login_items(
        items: list[dict[str, Any]],
        *,
        old_login_id: str,
        new_login_id: str,
        old_subject: str,
        new_subject: str,
    ) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any]]:
        old_auth_items = [
            item
            for item in items
            if item.get("pk") == _string_attr(f"AUTH#{old_subject}")
            and item.get("sk") == _string_attr("PROFILE")
        ]
        if len(old_auth_items) != 1:
            raise RuntimeError(
                f"Expected exactly one auth profile for subject={old_subject!r}, found {len(old_auth_items)}"
            )
        old_auth_item = old_auth_items[0]

        changed: list[dict[str, Any]] = []
        for original in items:
            item = copy.deepcopy(original)
            touched = False
            if item.get("login_id") == _string_attr(old_login_id):
                item["login_id"] = _string_attr(new_login_id)
                touched = True
            if item.get("owner_login_id") == _string_attr(old_login_id):
                item["owner_login_id"] = _string_attr(new_login_id)
                touched = True
            if item.get("auth_subject") == _string_attr(old_subject):
                item["auth_subject"] = _string_attr(new_subject)
                touched = True
            if original is old_auth_item:
                item["pk"] = _string_attr(f"AUTH#{new_subject}")
                item["auth_subject"] = _string_attr(new_subject)
                item["login_id"] = _string_attr(new_login_id)
                touched = True
            if touched:
                changed.append(item)

        new_auth_items = [
            item
            for item in changed
            if item.get("pk") == _string_attr(f"AUTH#{new_subject}")
            and item.get("sk") == _string_attr("PROFILE")
        ]
        if len(new_auth_items) != 1:
            raise RuntimeError("Replacement auth profile was not created exactly once")
        return changed, old_auth_item, new_auth_items[0]

    def _decorate_app_owner(self, app: dict[str, Any]) -> dict[str, Any]:
        owner_user_id = app.get("owner_user_id")
        if not isinstance(owner_user_id, str) or not owner_user_id:
            raise RuntimeError("App owner_user_id is invalid")
        name = self._display_name(owner_user_id)
        enriched = dict(app)
        if name is not None:
            enriched["owner_display_name"] = name
        return enriched

    def list_review_queue(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        return [
            self._decorate_app_owner(app)
            for app in super().list_review_queue(auth_subject, group_id)
        ]

    def list_mobile_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        return [
            self._decorate_app_owner(app)
            for app in super().list_mobile_apps(auth_subject)
        ]
