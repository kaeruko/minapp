from __future__ import annotations

import secrets
import time
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from phase2_backend import _number_attr
from phase3_backend import LAUNCH_TTL_SECONDS
from shop_backend import ShopAwsBackend


class ShopGuardedAwsBackend(ShopAwsBackend):
    """Shop backend that marks shop launch tokens and rechecks listing on use."""

    def create_shop_launch(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        _, version = self._current_shop_version(app_id)
        if _item_string(version, "version_id") != version_id:
            raise ApiProblem(
                409,
                "shop_version_stale",
                "ショップの作品が更新されました。一覧を更新してください。",
            )

        token = secrets.token_urlsafe(32)
        expires_at = int(time.time()) + LAUNCH_TTL_SECONDS
        item = {
            "pk": _string_attr(f"LAUNCH#{token}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("launch_token"),
            "source": _string_attr("shop"),
            "published_key": _string_attr(_item_string(version, "published_key")),
            "sha256": _string_attr(_item_string(version, "sha256")),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(_item_string(version, "group_id")),
            "issued_to_user_id": _string_attr(user.user_id),
            "expires_at": _number_attr(expires_at),
        }
        self._transact_put_new([item])
        return {
            "content_path": f"/launch/{token}/index.html",
            "expires_in": LAUNCH_TTL_SECONDS,
        }

    def get_launch_file(self, token: str, path: str) -> tuple[bytes, str]:
        token_item = self._get_item(pk=f"LAUNCH#{token}", sk="META")
        if token_item is None:
            return super().get_launch_file(token, path)

        raw_source = token_item.get("source")
        if raw_source is not None:
            source = _item_string(token_item, "source")
            if source != "shop":
                raise RuntimeError(f"Unsupported launch token source: {source!r}")
            app_id = _item_string(token_item, "app_id")
            version_id = _item_string(token_item, "version_id")
            _, current = self._current_shop_version(app_id)
            if _item_string(current, "version_id") != version_id:
                raise ApiProblem(
                    404,
                    "shop_launch_stale",
                    "このショップ作品は更新されたため、起動し直してください。",
                )

        return super().get_launch_file(token, path)
