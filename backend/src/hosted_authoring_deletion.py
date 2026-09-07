from __future__ import annotations

from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_backend import (
    _asset_manifest_string,
    _item_assets,
    _validate_content_id,
)
from hosted_catalog_backend import _optional_string
from hosted_platform_backend import _now_iso

_DYNAMODB_TRANSACTION_LIMIT = 100
_MISSING_OBJECT_CODES = {"404", "NoSuchKey", "NotFound"}


def delete_authoring_project(
    backend: Any,
    auth_subject: str,
    content_id: str,
) -> None:
    """Delete one Authoring work and its published app, if any.

    The operation is explicitly retryable. The first call atomically marks the
    content as deleting and removes its group-list index, which blocks further
    load/save/preview/publish work through the existing ``status == draft``
    checks. Cleanup then removes the ordinary published app, exact versioned S3
    objects referenced by Authoring manifests, and Authoring child metadata.
    The CONTENT META row is retained as a minimal tombstone so repeating the
    same DELETE is idempotent.
    """

    _validate_content_id(content_id)
    user = backend._user_by_auth_subject(auth_subject)
    current = backend._get_item(pk=f"CONTENT#{content_id}", sk="META")
    if current is None:
        raise ApiProblem(404, "content_not_found", "Authoring content was not found.")

    _validate_content_identity(current, content_id)
    group_id = _item_string(current, "group_id")
    owner_user_id = _item_string(current, "owner_user_id")
    backend._require_active_membership(user.user_id, group_id)
    if owner_user_id != user.user_id:
        raise ApiProblem(403, "forbidden", "You do not own this Authoring content.")

    status = _item_string(current, "status")
    deletion_state = _optional_string(current, "deletion_state")
    if status == "deleted":
        if deletion_state != "deleted":
            raise RuntimeError("Deleted Authoring tombstone has an invalid deletion state")
        return

    retrying = status == "deleting" and deletion_state == "deleting"
    if status == "draft":
        if deletion_state is not None:
            raise RuntimeError("Draft Authoring content unexpectedly has deletion_state")
        _validate_published_app_before_delete(backend, current)
        _begin_deletion(backend, current)
        current = backend._get_item(pk=f"CONTENT#{content_id}", sk="META")
        if current is None:
            raise RuntimeError("Authoring content disappeared while deletion was starting")
        status = _item_string(current, "status")
        deletion_state = _optional_string(current, "deletion_state")
        retrying = False

    if status != "deleting" or deletion_state != "deleting":
        raise ApiProblem(
            409,
            "content_not_editable",
            "Authoring content is not in a deletable state.",
        )

    _require_group_index_removed(backend, current)
    _delete_published_app(backend, auth_subject, current)

    revision_manifests = _content_manifests(backend, content_id, "REVISION#")
    published_manifests = _content_manifests(backend, content_id, "PUBLISHED#")
    object_refs = _collect_object_refs(
        backend,
        current,
        revision_manifests,
        published_manifests,
    )
    for bucket, key, sha256 in object_refs:
        _delete_exact_versioned_object(
            backend,
            bucket=bucket,
            key=key,
            expected_sha256=sha256,
            allow_missing=retrying,
        )

    child_items = [*revision_manifests, *published_manifests]
    player = backend._get_item(pk=f"CONTENT#{content_id}", sk="PLAYER")
    if player is not None:
        if _item_string(player, "entity") != "authoring_player_selection":
            raise RuntimeError("Authoring PLAYER row has an unexpected entity")
        if _item_string(player, "content_id") != content_id:
            raise RuntimeError("Authoring PLAYER row has a mismatched content_id")
        child_items.append(player)
    _delete_child_metadata(backend, child_items)
    _write_deleted_tombstone(backend, current)


def _validate_content_identity(item: dict[str, Any], content_id: str) -> None:
    entity = _item_string(item, "entity")
    if entity not in {"authoring_content", "authoring_content_tombstone"}:
        raise RuntimeError("Authoring content META has an unexpected entity")
    if _item_string(item, "content_id") != content_id:
        raise RuntimeError("Authoring content META has a mismatched content_id")


def _begin_deletion(backend: Any, current: dict[str, Any]) -> None:
    content_id = _item_string(current, "content_id")
    group_id = _item_string(current, "group_id")
    owner_user_id = _item_string(current, "owner_user_id")
    deleting_at = _now_iso()
    try:
        backend._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": backend._table_name,
                        "Key": {
                            "pk": _string_attr(f"CONTENT#{content_id}"),
                            "sk": _string_attr("META"),
                        },
                        "UpdateExpression": (
                            "SET deletion_state = :deleting, "
                            "deletion_started_at = :deleting_at, #status = :deleting"
                        ),
                        "ConditionExpression": (
                            "#status = :draft AND attribute_not_exists(deletion_state)"
                        ),
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {
                            ":draft": _string_attr("draft"),
                            ":deleting": _string_attr("deleting"),
                            ":deleting_at": _string_attr(deleting_at),
                        },
                    }
                },
                {
                    "Delete": {
                        "TableName": backend._table_name,
                        "Key": {
                            "pk": _string_attr(f"GROUP#{group_id}"),
                            "sk": _string_attr(f"CONTENT#{content_id}"),
                        },
                        "ConditionExpression": (
                            "attribute_exists(pk) AND owner_user_id = :owner_user_id"
                        ),
                        "ExpressionAttributeValues": {
                            ":owner_user_id": _string_attr(owner_user_id),
                        },
                    }
                },
            ]
        )
    except Exception as exc:
        if _aws_error_code(exc) != "TransactionCanceledException":
            raise
        latest = backend._get_item(pk=f"CONTENT#{content_id}", sk="META")
        if (
            latest is None
            or _item_string(latest, "status") != "deleting"
            or _optional_string(latest, "deletion_state") != "deleting"
        ):
            raise
        _require_group_index_removed(backend, latest)


def _require_group_index_removed(backend: Any, current: dict[str, Any]) -> None:
    group_id = _item_string(current, "group_id")
    content_id = _item_string(current, "content_id")
    index = backend._get_item(
        pk=f"GROUP#{group_id}",
        sk=f"CONTENT#{content_id}",
    )
    if index is not None:
        raise RuntimeError("Deleting Authoring content is still present in the group index")


def _validate_published_app_before_delete(backend: Any, current: dict[str, Any]) -> None:
    published_app_id = _optional_string(current, "published_app_id")
    if published_app_id is None:
        return
    app = backend._get_item(pk=f"APP#{published_app_id}", sk="META")
    group_index = backend._get_item(
        pk=f"GROUP#{_item_string(current, 'group_id')}",
        sk=f"APP#{published_app_id}",
    )
    if app is None or group_index is None:
        raise RuntimeError("Published Authoring app metadata is missing before deletion")
    _validate_published_app_scope(current, app)
    _validate_published_app_scope(current, group_index)


def _delete_published_app(
    backend: Any,
    auth_subject: str,
    current: dict[str, Any],
) -> None:
    published_app_id = _optional_string(current, "published_app_id")
    if published_app_id is None:
        return
    group_id = _item_string(current, "group_id")
    app = backend._get_item(pk=f"APP#{published_app_id}", sk="META")
    group_index = backend._get_item(
        pk=f"GROUP#{group_id}",
        sk=f"APP#{published_app_id}",
    )
    if app is None and group_index is None:
        return
    if app is None or group_index is None:
        raise RuntimeError("Published Authoring app deletion left partial metadata")
    _validate_published_app_scope(current, app)
    _validate_published_app_scope(current, group_index)
    backend.delete_hosted_app(auth_subject, group_id, published_app_id)


def _validate_published_app_scope(
    current: dict[str, Any],
    app: dict[str, Any],
) -> None:
    if _item_string(app, "source_kind") != "authoring":
        raise RuntimeError("Published app linked from Authoring content is not authoring-backed")
    if _item_string(app, "authoring_content_id") != _item_string(current, "content_id"):
        raise RuntimeError("Published app no longer belongs to this Authoring content")
    for field in ("group_id", "owner_user_id"):
        if _item_string(app, field) != _item_string(current, field):
            raise RuntimeError(f"Published Authoring app scope mismatch: {field}")


def _content_manifests(
    backend: Any,
    content_id: str,
    prefix: str,
) -> list[dict[str, Any]]:
    response = backend._dynamodb.query(
        TableName=backend._table_name,
        KeyConditionExpression="pk = :pk AND begins_with(sk, :manifest_prefix)",
        ExpressionAttributeValues={
            ":pk": _string_attr(f"CONTENT#{content_id}"),
            ":manifest_prefix": _string_attr(prefix),
        },
        ConsistentRead=True,
    )
    return backend._query_items(response)


def _collect_object_refs(
    backend: Any,
    current: dict[str, Any],
    revisions: list[dict[str, Any]],
    publications: list[dict[str, Any]],
) -> list[tuple[str, str, str]]:
    refs: dict[tuple[str, str], str] = {}
    for manifest in revisions:
        _validate_manifest_scope(current, manifest, "authoring_revision")
        _add_manifest_objects(refs, backend._upload_bucket, manifest)
    for manifest in publications:
        _validate_manifest_scope(current, manifest, "authoring_published_version")
        _add_manifest_objects(refs, backend._published_bucket, manifest)
    return [
        (bucket, key, refs[(bucket, key)])
        for bucket, key in sorted(refs)
    ]


def _validate_manifest_scope(
    current: dict[str, Any],
    manifest: dict[str, Any],
    expected_entity: str,
) -> None:
    if _item_string(manifest, "entity") != expected_entity:
        raise RuntimeError("Authoring manifest has an unexpected entity")
    for field in ("content_id", "group_id", "owner_user_id", "content_format"):
        if _item_string(manifest, field) != _item_string(current, field):
            raise RuntimeError(f"Authoring manifest scope mismatch: {field}")


def _add_manifest_objects(
    refs: dict[tuple[str, str], str],
    bucket: str,
    manifest: dict[str, Any],
) -> None:
    _add_object_ref(
        refs,
        bucket,
        _item_string(manifest, "document_key"),
        _item_string(manifest, "document_sha256"),
    )
    for asset in _item_assets(manifest).values():
        _add_object_ref(
            refs,
            bucket,
            _asset_manifest_string(asset, "key"),
            _asset_manifest_string(asset, "sha256"),
        )


def _add_object_ref(
    refs: dict[tuple[str, str], str],
    bucket: str,
    key: str,
    sha256: str,
) -> None:
    ref = (bucket, key)
    previous = refs.get(ref)
    if previous is not None and previous != sha256:
        raise RuntimeError("Authoring manifests disagree about an immutable object checksum")
    refs[ref] = sha256


def _delete_exact_versioned_object(
    backend: Any,
    *,
    bucket: str,
    key: str,
    expected_sha256: str,
    allow_missing: bool,
) -> None:
    try:
        head = backend._s3.head_object(Bucket=bucket, Key=key)
    except Exception as exc:
        if allow_missing and _aws_error_code(exc) in _MISSING_OBJECT_CODES:
            # A retry may reach an object whose exact version was already
            # physically removed by an earlier attempt.
            return
        raise

    metadata = head.get("Metadata")
    if not isinstance(metadata, dict) or metadata.get("sha256") != expected_sha256:
        raise RuntimeError("Authoring S3 object checksum metadata does not match its manifest")
    version_id = head.get("VersionId")
    if not isinstance(version_id, str) or not version_id:
        raise RuntimeError("Versioned Authoring S3 object has no VersionId")
    backend._s3.delete_object(
        Bucket=bucket,
        Key=key,
        VersionId=version_id,
    )


def _delete_child_metadata(backend: Any, items: list[dict[str, Any]]) -> None:
    unique: dict[tuple[str, str], dict[str, Any]] = {}
    for item in items:
        key = (_item_string(item, "pk"), _item_string(item, "sk"))
        unique[key] = item
    keys = sorted(unique)
    for offset in range(0, len(keys), _DYNAMODB_TRANSACTION_LIMIT):
        chunk = keys[offset : offset + _DYNAMODB_TRANSACTION_LIMIT]
        backend._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Delete": {
                        "TableName": backend._table_name,
                        "Key": {
                            "pk": _string_attr(pk),
                            "sk": _string_attr(sk),
                        },
                    }
                }
                for pk, sk in chunk
            ]
        )


def _write_deleted_tombstone(backend: Any, current: dict[str, Any]) -> None:
    content_id = _item_string(current, "content_id")
    deleted_at = _now_iso()
    tombstone = {
        "pk": _string_attr(f"CONTENT#{content_id}"),
        "sk": _string_attr("META"),
        "entity": _string_attr("authoring_content_tombstone"),
        "content_id": _string_attr(content_id),
        "group_id": _string_attr(_item_string(current, "group_id")),
        "owner_user_id": _string_attr(_item_string(current, "owner_user_id")),
        "content_format": _string_attr(_item_string(current, "content_format")),
        "status": _string_attr("deleted"),
        "deletion_state": _string_attr("deleted"),
        "deleted_at": _string_attr(deleted_at),
    }
    backend._dynamodb.transact_write_items(
        TransactItems=[
            {
                "Put": {
                    "TableName": backend._table_name,
                    "Item": tombstone,
                    "ConditionExpression": "deletion_state = :deleting",
                    "ExpressionAttributeValues": {
                        ":deleting": _string_attr("deleting"),
                    },
                }
            }
        ]
    )
