from __future__ import annotations

from typing import Any

from hosted_shop_backend import HostedShopBackend


class HostedShopGuardedBackend(HostedShopBackend):
    """Fail-fast validation for Hosted shop visibility mutations."""

    def _shop_visibility_update(
        self,
        *,
        pk: str,
        sk: str,
        owner_user_id: str,
        visibility: str,
        listed_at: str | None,
    ) -> dict[str, Any]:
        if visibility == "listed":
            if listed_at is None or not listed_at:
                raise ValueError("listed_at is required when visibility is listed")
        elif visibility == "unlisted":
            if listed_at is not None:
                raise ValueError("listed_at must be None when visibility is unlisted")
        else:
            raise ValueError(f"unsupported shop visibility: {visibility!r}")
        return super()._shop_visibility_update(
            pk=pk,
            sk=sk,
            owner_user_id=owner_user_id,
            visibility=visibility,
            listed_at=listed_at,
        )
