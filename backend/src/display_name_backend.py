from __future__ import annotations

from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from phase2_backend import _optional_item_string
from phase4_moderation_backend import Phase4ModerationAwsBackend


class DisplayNameAwsBackend(Phase4ModerationAwsBackend):
    """Optional user display names without requiring a migration of existing user items."""

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
