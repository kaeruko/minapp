"""Prepare list-route SDK clients during Lambda's provisioned initialization.

Constructing the existing backends only initializes clients; it neither reads
user content nor submits synthetic requests. Authorization and abuse controls
remain in the existing request handler.
"""

from __future__ import annotations

import os
from typing import Any

import abuse_entry
import hosted_authoring_entry
import hosted_entry
import hosted_handler


def prepare_list_backends() -> None:
    hosted_handler._get_backend()
    hosted_entry._get_backend()
    hosted_authoring_entry._get_backend()


if os.environ.get("AWS_LAMBDA_INITIALIZATION_TYPE") == "provisioned-concurrency":
    prepare_list_backends()


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    return abuse_entry.hosted_lambda_handler(event, context)
