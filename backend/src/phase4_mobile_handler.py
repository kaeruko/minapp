from __future__ import annotations

from typing import Any

import phase3_handler
import shop_handler
from shop_guarded_backend import ShopGuardedAwsBackend


def _shared_backend() -> ShopGuardedAwsBackend:
    backend = phase3_handler._BACKEND
    if backend is None:
        resolved = ShopGuardedAwsBackend.from_environment()
        phase3_handler._BACKEND = resolved
        shop_handler._BACKEND = resolved
        return resolved
    if not isinstance(backend, ShopGuardedAwsBackend):
        raise RuntimeError("Mobile API backend was initialized with an incompatible backend type")
    if shop_handler._BACKEND is None:
        shop_handler._BACKEND = backend
    elif shop_handler._BACKEND is not backend:
        raise RuntimeError("Mobile and shop handlers must share the same backend instance")
    return backend


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    _shared_backend()
    raw_path = event.get("rawPath") if isinstance(event, dict) else None
    if isinstance(raw_path, str) and (
        raw_path.startswith("/shop/") or raw_path.endswith("/shop-visibility")
    ):
        return shop_handler.lambda_handler(event, context)
    return phase3_handler.lambda_handler(event, context)
