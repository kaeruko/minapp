from __future__ import annotations

from typing import Any

from shop_backend import ShopAwsBackend


class ShopLifecycleBackend(ShopAwsBackend):
    """Author lifecycle responses enriched with app-level shop visibility."""

    def list_my_apps_lifecycle(self, auth_subject: str) -> list[dict[str, Any]]:
        apps = super().list_my_apps_lifecycle(auth_subject)
        visibility_by_app: dict[str, str] = {}
        result: list[dict[str, Any]] = []
        for app in apps:
            app_id = app.get("app_id")
            if not isinstance(app_id, str) or not app_id:
                raise RuntimeError("Lifecycle app has invalid app_id")
            visibility = visibility_by_app.get(app_id)
            if visibility is None:
                visibility = self._shop_visibility(self._app_meta_item(app_id))
                visibility_by_app[app_id] = visibility
            enriched = dict(app)
            enriched["shop_visibility"] = visibility
            result.append(enriched)
        return result
