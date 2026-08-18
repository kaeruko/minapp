from __future__ import annotations

from typing import Any

import phase3_handler
from display_name_backend import DisplayNameAwsBackend


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if phase3_handler._BACKEND is None:
        phase3_handler._BACKEND = DisplayNameAwsBackend.from_environment()
    return phase3_handler.lambda_handler(event, context)
