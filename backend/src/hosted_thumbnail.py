from __future__ import annotations

from typing import Any

from errors import ApiProblem
from hosted_app_management import _author_editable_app
from hosted_catalog_backend import _optional_string
from hosted_platform_backend import _now_iso
from aws_backend import _string_attr

MAX_THUMBNAIL_BYTES = 192 * 1024
_ALLOWED_CONTENT_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})


def _binary_attr(data: bytes) -> dict[str, bytes]:
    return {"B": data}


def _validate_thumbnail_bytes(data: bytes, content_type: str) -> None:
    if not isinstance(data, bytes) or not data:
        raise ApiProblem(400, "invalid_thumbnail", "サムネイル画像が空です。")
    if len(data) > MAX_THUMBNAIL_BYTES:
        raise ApiProblem(
            413,
            "thumbnail_too_large",
            "サムネイル画像は192KB以下にしてください。",
        )
    if content_type not in _ALLOWED_CONTENT_TYPES:
        raise ApiProblem(
            415,
            "unsupported_media_type",
            "サムネイルはJPEG・PNG・WebPのいずれかにしてください。",
        )

    if content_type == "image/png":
        valid_signature = data.startswith(b"\x89PNG\r\n\x1a\n")
    elif content_type == "image/jpeg":
        valid_signature = data.startswith(b"\xff\xd8\xff")
    else:
        valid_signature = len(data) >= 12 and data.startswith(b"RIFF") and data[8:12] == b"WEBP"

    if not valid_signature:
        raise ApiProblem(
            400,
            "invalid_thumbnail",
            "画像データとContent-Typeが一致しません。",
        )


def set_thumbnail(
    backend: Any,
    auth_subject: str,
    app_id: str,
    *,
    data: bytes,
    content_type: str,
) -> dict[str, Any]:
    _validate_thumbnail_bytes(data, content_type)
    _, app = _author_editable_app(backend, auth_subject, app_id)
    updated_at = _now_iso()

    backend._dynamodb.transact_write_items(
        TransactItems=[
            {
                "Update": {
                    "TableName": backend._table_name,
                    "Key": {
                        "pk": _string_attr(f"APP#{app_id}"),
                        "sk": _string_attr("META"),
                    },
                    "UpdateExpression": (
                        "SET thumbnail_bytes = :thumbnail_bytes, "
                        "thumbnail_content_type = :thumbnail_content_type, "
                        "thumbnail_updated_at = :thumbnail_updated_at"
                    ),
                    "ConditionExpression": (
                        "attribute_exists(pk) AND attribute_not_exists(deletion_state)"
                    ),
                    "ExpressionAttributeValues": {
                        ":thumbnail_bytes": _binary_attr(data),
                        ":thumbnail_content_type": _string_attr(content_type),
                        ":thumbnail_updated_at": _string_attr(updated_at),
                    },
                }
            }
        ]
    )
    return {
        "app_id": app_id,
        "content_type": content_type,
        "bytes": len(data),
        "updated_at": updated_at,
    }


def get_thumbnail(
    backend: Any,
    auth_subject: str,
    app_id: str,
) -> tuple[bytes, str]:
    _, app = _author_editable_app(backend, auth_subject, app_id)
    raw = app.get("thumbnail_bytes")
    if raw is None:
        raise ApiProblem(404, "thumbnail_not_found", "サムネイルは設定されていません。")
    if not isinstance(raw, dict):
        raise RuntimeError("DynamoDB thumbnail_bytes is not an attribute object")
    stored = raw.get("B")
    if isinstance(stored, bytearray):
        data = bytes(stored)
    elif isinstance(stored, bytes):
        data = stored
    else:
        raise RuntimeError("DynamoDB thumbnail_bytes is not binary")

    content_type = _optional_string(app, "thumbnail_content_type")
    if content_type is None or content_type not in _ALLOWED_CONTENT_TYPES:
        raise RuntimeError("Stored thumbnail has an invalid content type")
    _validate_thumbnail_bytes(data, content_type)
    return data, content_type
