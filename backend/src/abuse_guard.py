from __future__ import annotations

import hashlib
import ipaddress
import os
import time
from dataclasses import dataclass
from typing import Any

from errors import ApiProblem


@dataclass(frozen=True)
class LimitRule:
    subject: str
    max_attempts: int
    window_seconds: int


_LIMITS: dict[str, tuple[LimitRule, ...]] = {
    "register": (
        LimitRule("ip", 8, 15 * 60),
        LimitRule("login_id", 3, 15 * 60),
        LimitRule("ip", 30, 24 * 60 * 60),
    ),
    "recover": (
        LimitRule("ip", 12, 15 * 60),
        LimitRule("login_id", 6, 15 * 60),
    ),
    "login": (
        LimitRule("ip", 40, 15 * 60),
        LimitRule("login_id", 10, 15 * 60),
    ),
}

_RATE_LIMIT_MESSAGE = "リクエストが多すぎます。しばらくしてからもう一度お試しください。"
_GUARD: "AbuseGuard | None" = None


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _aws_error_code(exc: Exception) -> str | None:
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return None
    error = response.get("Error")
    if not isinstance(error, dict):
        return None
    code = error.get("Code")
    return code if isinstance(code, str) else None


def source_ip_from_event(event: dict[str, Any]) -> str:
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        raise ValueError("requestContext must be an object")
    http = request_context.get("http")
    if not isinstance(http, dict):
        raise ValueError("requestContext.http must be an object")
    source_ip = http.get("sourceIp")
    if not isinstance(source_ip, str) or not source_ip:
        raise ValueError("requestContext.http.sourceIp must be a non-empty string")
    try:
        return ipaddress.ip_address(source_ip).compressed
    except ValueError as exc:
        raise ValueError("requestContext.http.sourceIp must be a valid IP address") from exc


class AbuseGuard:
    def __init__(
        self,
        *,
        dynamodb: Any,
        table_name: str,
        hash_salt: str,
        now_fn: Any = time.time,
    ) -> None:
        if not table_name:
            raise ValueError("table_name must not be empty")
        if not hash_salt:
            raise ValueError("hash_salt must not be empty")
        self._dynamodb = dynamodb
        self._table_name = table_name
        self._hash_salt = hash_salt
        self._now_fn = now_fn

    @classmethod
    def from_environment(cls) -> "AbuseGuard":
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required outside the AWS Lambda runtime. Install the development requirements explicitly."
            ) from exc
        data_table_name = _required_env("DATA_TABLE_NAME")
        tenant_id = _required_env("TENANT_ID")
        return cls(
            dynamodb=boto3.client("dynamodb"),
            table_name=f"{data_table_name}-abuse",
            hash_salt=tenant_id,
        )

    def check(self, action: str, *, source_ip: str, login_id: str | None = None) -> None:
        rules = _LIMITS.get(action)
        if rules is None:
            raise ValueError(f"Unsupported abuse-control action: {action}")
        canonical_ip = ipaddress.ip_address(source_ip).compressed
        for rule in rules:
            if rule.subject == "ip":
                subject_value = canonical_ip
            elif rule.subject == "login_id":
                if not isinstance(login_id, str) or not login_id:
                    raise ValueError(f"login_id is required for abuse-control action {action}")
                subject_value = login_id
            else:
                raise RuntimeError(f"Unsupported abuse-control subject: {rule.subject}")
            self._consume(action, rule, subject_value)

    def _consume(self, action: str, rule: LimitRule, subject_value: str) -> None:
        now = int(self._now_fn())
        window_start = now - (now % rule.window_seconds)
        digest = hashlib.sha256(
            f"{self._hash_salt}\0{action}\0{rule.subject}\0{subject_value}".encode("utf-8")
        ).hexdigest()
        pk = f"V1#{action}#{rule.subject}#{rule.window_seconds}#{window_start}#{digest}"
        expires_at_epoch = window_start + rule.window_seconds + 24 * 60 * 60
        try:
            self._dynamodb.update_item(
                TableName=self._table_name,
                Key={"pk": {"S": pk}},
                UpdateExpression="SET #expires = :expires ADD #count :one",
                ConditionExpression="attribute_not_exists(#count) OR #count < :limit",
                ExpressionAttributeNames={
                    "#count": "attempt_count",
                    "#expires": "expires_at_epoch",
                },
                ExpressionAttributeValues={
                    ":one": {"N": "1"},
                    ":limit": {"N": str(rule.max_attempts)},
                    ":expires": {"N": str(expires_at_epoch)},
                },
            )
        except Exception as exc:
            if _aws_error_code(exc) == "ConditionalCheckFailedException":
                raise ApiProblem(429, "rate_limited", _RATE_LIMIT_MESSAGE) from exc
            raise RuntimeError("Abuse rate-limit storage update failed.") from exc


def get_abuse_guard() -> AbuseGuard:
    global _GUARD
    if _GUARD is None:
        _GUARD = AbuseGuard.from_environment()
    return _GUARD
