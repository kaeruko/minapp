from __future__ import annotations

import time
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from phase2_backend import _item_number, _now_iso
from phase4_backend import Phase4AwsBackend


class Phase4ModerationAwsBackend(Phase4AwsBackend):
    """Teacher rejection and publication-stop rules layered on Phase 4."""

    @staticmethod
    def _latest_publication_decision(items: list[dict[str, Any]]) -> dict[str, Any] | None:
        decisions = [
            item
            for item in items
            if _item_string(item, "status") in {"approved", "unpublished"}
        ]
        if not decisions:
            return None
        for item in decisions:
            _item_string(item, "reviewed_at")
        return max(
            decisions,
            key=lambda item: (
                _item_string(item, "reviewed_at"),
                _item_string(item, "created_at"),
                _item_string(item, "version_id"),
            ),
        )

    def reject_app(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        self._require_active_app(app_id)
        teacher = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        group_id = _item_string(version, "group_id")
        self._require_teacher_membership(teacher.user_id, group_id)
        if _item_string(version, "status") != "pending_review":
            raise ApiProblem(
                409,
                "invalid_app_state",
                "先生の確認待ちの作品だけ差し戻せます。",
            )

        rejected_at = _now_iso()
        self._transition_version(
            version,
            expected_status="pending_review",
            new_status="rejected",
            extra={
                "rejected_at": rejected_at,
                "reviewed_by": teacher.user_id,
            },
        )
        version["status"] = _string_attr("rejected")
        version["rejected_at"] = _string_attr(rejected_at)
        version["reviewed_by"] = _string_attr(teacher.user_id)
        return self._public_version(version)

    def unpublish_app(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        self._require_active_app(app_id)
        teacher = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        group_id = _item_string(version, "group_id")
        self._require_teacher_membership(teacher.user_id, group_id)

        if _item_string(version, "status") != "approved":
            raise ApiProblem(
                409,
                "app_not_published",
                "現在公開中の作品だけ公開を停止できます。",
            )

        latest = self._latest_publication_decision(self._version_items(app_id))
        if latest is None:
            raise RuntimeError("Approved app has no publication decision")
        if _item_string(latest, "status") != "approved":
            raise ApiProblem(
                409,
                "app_not_published",
                "この作品はすでに公開停止中です。",
            )
        if _item_string(latest, "version_id") != version_id:
            raise ApiProblem(
                409,
                "old_version_not_published",
                "この作品には新しい公開版があります。一覧を更新してください。",
            )

        unpublished_at = _now_iso()
        self._transition_version(
            version,
            expected_status="approved",
            new_status="unpublished",
            extra={
                "unpublished_at": unpublished_at,
                "unpublished_by": teacher.user_id,
            },
        )
        version["status"] = _string_attr("unpublished")
        version["unpublished_at"] = _string_attr(unpublished_at)
        version["unpublished_by"] = _string_attr(teacher.user_id)
        return self._public_version(version)

    def list_my_apps_lifecycle(self, auth_subject: str) -> list[dict[str, Any]]:
        apps = super().list_my_apps_lifecycle(auth_subject)
        by_app: dict[str, list[dict[str, Any]]] = {}
        for app in apps:
            app_id = app.get("app_id")
            if not isinstance(app_id, str) or not app_id:
                raise RuntimeError("Lifecycle app_id is invalid")
            by_app.setdefault(app_id, []).append(app)

        for versions in by_app.values():
            decisions = [
                app
                for app in versions
                if app.get("status") in {"approved", "unpublished"}
            ]
            for app in versions:
                app["is_published"] = False
            if not decisions:
                continue
            for app in decisions:
                reviewed_at = app.get("reviewed_at")
                created_at = app.get("created_at")
                version_id = app.get("version_id")
                if not isinstance(reviewed_at, str) or not reviewed_at:
                    raise RuntimeError("Publication decision has no reviewed_at")
                if not isinstance(created_at, str) or not created_at:
                    raise RuntimeError("Publication decision has no created_at")
                if not isinstance(version_id, str) or not version_id:
                    raise RuntimeError("Publication decision has no version_id")
            latest = max(
                decisions,
                key=lambda app: (app["reviewed_at"], app["created_at"], app["version_id"]),
            )
            if latest["status"] == "approved":
                latest["is_published"] = True
        return apps

    def list_mobile_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        candidates = super().list_mobile_apps(auth_subject)
        visible: list[dict[str, Any]] = []
        for candidate in candidates:
            app_id = candidate.get("app_id")
            version_id = candidate.get("version_id")
            if not isinstance(app_id, str) or not app_id:
                raise RuntimeError("Mobile catalogue app_id is invalid")
            if not isinstance(version_id, str) or not version_id:
                raise RuntimeError("Mobile catalogue version_id is invalid")

            latest = self._latest_publication_decision(self._version_items(app_id))
            if latest is None:
                raise RuntimeError("Approved mobile app has no publication decision")
            latest_status = _item_string(latest, "status")
            if latest_status == "unpublished":
                continue
            if latest_status != "approved":
                raise RuntimeError(f"Unsupported publication decision: {latest_status!r}")
            if _item_string(latest, "version_id") != version_id:
                raise RuntimeError("Mobile catalogue did not select the latest published version")
            visible.append(candidate)
        return visible

    def create_launch(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        self._require_active_app(app_id)
        latest = self._latest_publication_decision(self._version_items(app_id))
        if latest is None:
            raise ApiProblem(409, "app_not_published", "この作品は公開されていません。")
        if _item_string(latest, "status") == "unpublished":
            raise ApiProblem(409, "app_unpublished", "この作品は公開停止中です。")
        if _item_string(latest, "status") != "approved":
            raise RuntimeError("Latest publication decision has an unsupported status")
        if _item_string(latest, "version_id") != version_id:
            raise ApiProblem(
                409,
                "old_version_not_published",
                "この作品には新しい公開版があります。一覧を更新してください。",
            )
        return super().create_launch(auth_subject, app_id, version_id)

    def get_launch_file(self, token: str, path: str) -> tuple[bytes, str]:
        token_item = self._get_item(pk=f"LAUNCH#{token}", sk="META")
        if token_item is None:
            raise ApiProblem(404, "launch_not_found", "起動URLが無効です。")
        if _item_number(token_item, "expires_at") < int(time.time()):
            raise ApiProblem(404, "launch_expired", "起動URLの有効期限が切れました。")

        app_id = _item_string(token_item, "app_id")
        version_id = _item_string(token_item, "version_id")
        version = self._version_item(app_id, version_id)
        if _item_string(version, "status") != "approved":
            raise ApiProblem(404, "launch_unpublished", "このアプリは公開停止されています。")
        return super().get_launch_file(token, path)
