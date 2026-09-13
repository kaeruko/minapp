from __future__ import annotations

from hosted_shop_managed_backend import HostedShopManagedBackend
from hosted_shop_runtime_backend import HostedShopRuntimeBackend


class HostedGirlsShopBackend(HostedShopRuntimeBackend, HostedShopManagedBackend):
    """Final Girls shop backend: cross-group catalog, managed listing, isolated Runtime."""

    pass
