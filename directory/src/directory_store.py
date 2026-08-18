from __future__ import annotations

import time
from typing import Any, Mapping


class DuplicateRecordError(RuntimeError):
    pass


class ConcurrentUpdateError(RuntimeError):
    pass


def _s(value: str) -> dict[str, str]:
    if not isinstance(value, str) or not value:
        raise ValueError("DynamoDB string value must be non-empty")
    return {"S": value}


def _n(value: int) -> dict[str, str]:
    if not isinstance(value, int):
        raise ValueError("DynamoDB numeric value must be an integer")
    return {"N": str(value)}


def _decode(item: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if not item:
        return None
    result: dict[str, Any] = {}
    for key, raw in item.items():
        if not isinstance(raw, dict):
            raise RuntimeError(f"Invalid DynamoDB attribute for {key}")
        if "S" in raw:
            result[key] = raw["S"]
        elif "N" in raw:
            number = raw["N"]
            result[key] = int(number)
        elif "BOOL" in raw:
            result[key] = bool(raw["BOOL"])
        else:
            raise RuntimeError(f"Unsupported DynamoDB attribute for {key}")
    return result


def _encode(item: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for key, value in item.items():
        if isinstance(value, bool):
            result[key] = {"BOOL": value}
        elif isinstance(value, int):
            result[key] = _n(value)
        elif isinstance(value, str):
            result[key] = _s(value)
        else:
            raise ValueError(f"Unsupported DynamoDB value for {key}")
    return result


class DirectoryStore:
    def __init__(self, table_name: str, client: Any | None = None) -> None:
        if not isinstance(table_name, str) or not table_name:
            raise ValueError("table_name must be non-empty")
        self.table_name = table_name
        self._client = client

    @classmethod
    def from_environment(cls, environ: Mapping[str, str]) -> "DirectoryStore":
        table_name = environ.get("DIRECTORY_TABLE_NAME")
        if not isinstance(table_name, str) or not table_name:
            raise RuntimeError("DIRECTORY_TABLE_NAME is required")
        return cls(table_name)

    @property
    def client(self) -> Any:
        if self._client is None:
            import boto3

            self._client = boto3.client("dynamodb")
        return self._client

    @staticmethod
    def tenant_key(tenant_id: str) -> dict[str, dict[str, str]]:
        return {"PK": _s(f"TENANT#{tenant_id}"), "SK": _s("META")}

    @staticmethod
    def code_key(code_hash: str) -> dict[str, dict[str, str]]:
        return {"PK": _s(f"CODE#{code_hash}"), "SK": _s("META")}

    def get_tenant(self, tenant_id: str) -> dict[str, Any] | None:
        response = self.client.get_item(
            TableName=self.table_name,
            Key=self.tenant_key(tenant_id),
            ConsistentRead=True,
        )
        return _decode(response.get("Item"))

    def get_code_mapping(self, code_hash: str) -> dict[str, Any] | None:
        response = self.client.get_item(
            TableName=self.table_name,
            Key=self.code_key(code_hash),
            ConsistentRead=True,
        )
        return _decode(response.get("Item"))

    def consume_rate_limit(
        self,
        subject_hash: str,
        *,
        now_epoch: int,
        window_seconds: int,
        request_limit: int,
    ) -> bool:
        window_start = now_epoch - (now_epoch % window_seconds)
        key = {
            "PK": _s(f"RATE#{subject_hash}#{window_start}"),
            "SK": _s("META"),
        }
        try:
            self.client.update_item(
                TableName=self.table_name,
                Key=key,
                UpdateExpression="SET expires_at = :expires ADD request_count :one",
                ConditionExpression="attribute_not_exists(request_count) OR request_count < :limit",
                ExpressionAttributeValues={
                    ":expires": _n(window_start + window_seconds * 2),
                    ":one": _n(1),
                    ":limit": _n(request_limit),
                },
            )
            return True
        except Exception as exc:
            error = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error == "ConditionalCheckFailedException":
                return False
            raise

    def create_tenant(
        self,
        tenant: Mapping[str, Any],
        code_record: Mapping[str, Any],
        audit_record: Mapping[str, Any],
    ) -> None:
        try:
            self.client.transact_write_items(
                TransactItems=[
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(tenant),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(code_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(audit_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                ]
            )
        except Exception as exc:
            error = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error in {"TransactionCanceledException", "ConditionalCheckFailedException"}:
                raise DuplicateRecordError("tenant or classroom code already exists") from exc
            raise

    def update_endpoint(
        self,
        *,
        tenant_id: str,
        expected_revision: int,
        api_base_url: str,
        api_protocol_version: int,
        updated_at: str,
        audit_record: Mapping[str, Any],
    ) -> None:
        try:
            self.client.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self.table_name,
                            "Key": self.tenant_key(tenant_id),
                            "UpdateExpression": (
                                "SET api_base_url = :url, api_protocol_version = :protocol, "
                                "config_revision = :next_revision, updated_at = :updated"
                            ),
                            "ConditionExpression": "config_revision = :expected_revision",
                            "ExpressionAttributeValues": {
                                ":url": _s(api_base_url),
                                ":protocol": _n(api_protocol_version),
                                ":next_revision": _n(expected_revision + 1),
                                ":updated": _s(updated_at),
                                ":expected_revision": _n(expected_revision),
                            },
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(audit_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                ]
            )
        except Exception as exc:
            error = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error in {"TransactionCanceledException", "ConditionalCheckFailedException"}:
                raise ConcurrentUpdateError("tenant configuration changed concurrently") from exc
            raise

    def set_status(
        self,
        *,
        tenant_id: str,
        current_status: str,
        new_status: str,
        updated_at: str,
        audit_record: Mapping[str, Any],
    ) -> None:
        try:
            self.client.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self.table_name,
                            "Key": self.tenant_key(tenant_id),
                            "UpdateExpression": "SET #status = :new_status, updated_at = :updated",
                            "ConditionExpression": "#status = :current_status",
                            "ExpressionAttributeNames": {"#status": "status"},
                            "ExpressionAttributeValues": {
                                ":new_status": _s(new_status),
                                ":current_status": _s(current_status),
                                ":updated": _s(updated_at),
                            },
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(audit_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                ]
            )
        except Exception as exc:
            error = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error in {"TransactionCanceledException", "ConditionalCheckFailedException"}:
                raise ConcurrentUpdateError("tenant status changed concurrently") from exc
            raise

    def rotate_code(
        self,
        *,
        tenant_id: str,
        old_code_hash: str,
        new_code_record: Mapping[str, Any],
        updated_at: str,
        audit_record: Mapping[str, Any],
    ) -> None:
        new_hash = str(new_code_record["code_hash"])
        try:
            self.client.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self.table_name,
                            "Key": self.code_key(old_code_hash),
                            "UpdateExpression": "SET #status = :rotated, rotated_at = :updated",
                            "ConditionExpression": "tenant_id = :tenant_id AND #status = :active",
                            "ExpressionAttributeNames": {"#status": "status"},
                            "ExpressionAttributeValues": {
                                ":tenant_id": _s(tenant_id),
                                ":active": _s("active"),
                                ":rotated": _s("rotated"),
                                ":updated": _s(updated_at),
                            },
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(new_code_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                    {
                        "Update": {
                            "TableName": self.table_name,
                            "Key": self.tenant_key(tenant_id),
                            "UpdateExpression": "SET current_code_hash = :new_hash, updated_at = :updated",
                            "ConditionExpression": "current_code_hash = :old_hash",
                            "ExpressionAttributeValues": {
                                ":new_hash": _s(new_hash),
                                ":old_hash": _s(old_code_hash),
                                ":updated": _s(updated_at),
                            },
                        }
                    },
                    {
                        "Put": {
                            "TableName": self.table_name,
                            "Item": _encode(audit_record),
                            "ConditionExpression": "attribute_not_exists(PK)",
                        }
                    },
                ]
            )
        except Exception as exc:
            error = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error in {"TransactionCanceledException", "ConditionalCheckFailedException"}:
                raise DuplicateRecordError("classroom code collision or concurrent rotation") from exc
            raise

    def now_epoch(self) -> int:
        return int(time.time())
