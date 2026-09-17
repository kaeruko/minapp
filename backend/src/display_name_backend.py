from __future__ import annotations

from typing import Any

from display_name_store import read_display_name, write_display_name
from errors import ApiProblem
from phase4_moderation_backend import Phase4ModerationAwsBackend


class DisplayNameAwsBackend(Phase4ModerationAwsBackend):
    """Optional user display names without requiring a migration of existing user items."""

    def _display_name(self, user_id: str) -> str | None:
        return read_display_name(self, user_id)

    def _write_display_name(self, user_id: str, display_name: str) -> None:
        write_display_name(self, user_id, display_name)

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
