from __future__ import annotations

from typing import Any

from hosted_shop_managed_backend import HostedShopManagedBackend
from hosted_shop_runtime_backend import HostedShopRuntimeBackend
from hosted_user_state_backend import HostedUserStateBackend


class HostedGirlsShopBackend(HostedShopRuntimeBackend, HostedShopManagedBackend):
    """Final Girls shop backend: cross-group catalog, managed listing, isolated Runtime."""

    def list_group_apps(
        self, auth_subject: str, group_id: str
    ) -> list[dict[str, Any]]:
        # The shop is additive. Do not inject shop-only fields into the existing
        # group-app response contract consumed throughout Girls.
        return HostedUserStateBackend.list_group_apps(self, auth_subject, group_id)
