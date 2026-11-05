from __future__ import annotations

from hosted_girls_shop_backend import HostedConsumerBackend
from hosted_preview_state_backend import HostedPreviewStateBackend


class HostedShopPreviewStateBackend(HostedConsumerBackend, HostedPreviewStateBackend):
    """Runtime implementation for group, Shop, and ephemeral Preview sessions.

    Shop Runtime sessions use an app-scoped namespace that must not require
    membership in the source group. Ordinary group sessions still require
    membership, and Preview state retains its separate ephemeral store.

    MRO intentionally resolves _consume_runtime_request from
    HostedShopRuntimeBackend and get_runtime_user_state from
    HostedPreviewStateBackend.
    """
