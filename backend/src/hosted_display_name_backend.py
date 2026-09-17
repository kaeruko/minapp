from __future__ import annotations

from typing import Any

from display_name_store import read_display_name, write_display_name
from hosted_user_state_backend import HostedUserStateBackend


class HostedDisplayNameBackend(HostedUserStateBackend):
    """Hosted identity plus the shared optional display-name storage contract."""

    def get_my_display_name(self, auth_subject: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "display_name": read_display_name(self, user.user_id),
        }

    def set_my_display_name(
        self,
        auth_subject: str,
        display_name: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        write_display_name(self, user.user_id, display_name)
        return {
            "user_id": user.user_id,
            "login_id": user.login_id,
            "role": user.role,
            "display_name": display_name,
        }

    def list_members(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        members = super().list_members(auth_subject, group_id)
        result: list[dict[str, Any]] = []
        for member in members:
            user_id = member.get("user_id")
            if not isinstance(user_id, str) or not user_id:
                raise RuntimeError("Hosted member user_id is invalid")
            enriched = dict(member)
            enriched["display_name"] = read_display_name(self, user_id)
            result.append(enriched)
        return result
