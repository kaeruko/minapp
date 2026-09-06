from __future__ import annotations

import hashlib
import uuid
from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_authoring_backend import (
    HostedAuthoringBackend,
    _assets_json,
    _document_bytes,
    _validate_content_id,
    validate_content_format,
)
from hosted_platform_backend import _now_iso, _number_attr


class HostedAuthoringIndexedBackend(HostedAuthoringBackend):
    """Authoring storage with an explicit group -> content discovery index.

    The index is written in the same DynamoDB transaction as content metadata
    and revision 1. Listing never scans the metadata table and never silently
    skips a stale/corrupt index entry owned by the current user.
    """

    def create_authoring_project(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str,
        document: dict[str, Any],
    ) -> dict[str, Any]:
        content_format = validate_content_format(content_format)
        document_bytes = _document_bytes(document)
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)

        content_id = uuid.uuid4().hex
        revision = 1
        created_at = _now_iso()
        document_key = self._document_key(group_id, content_id, revision)
        document_sha256 = hashlib.sha256(document_bytes).hexdigest()
        assets: dict[str, dict[str, Any]] = {}

        self._put_immutable_object(
            key=document_key,
            data=document_bytes,
            content_type="application/json; charset=utf-8",
            sha256=document_sha256,
        )

        meta = {
            "pk": _string_attr(f"CONTENT#{content_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("authoring_content"),
            "content_id": _string_attr(content_id),
            "group_id": _string_attr(group_id),
            "owner_user_id": _string_attr(user.user_id),
            "content_format": _string_attr(content_format),
            "status": _string_attr("draft"),
            "draft_revision": _number_attr(revision),
            "document_key": _string_attr(document_key),
            "document_sha256": _string_attr(document_sha256),
            "document_bytes": _number_attr(len(document_bytes)),
            "assets_json": _string_attr(_assets_json(assets)),
            "created_at": _string_attr(created_at),
            "updated_at": _string_attr(created_at),
        }
        manifest = self._revision_manifest(
            meta,
            revision=revision,
            created_at=created_at,
        )
        index = {
            "pk": _string_attr(f"GROUP#{group_id}"),
            "sk": _string_attr(f"CONTENT#{content_id}"),
            "entity": _string_attr("authoring_content_index"),
            "content_id": _string_attr(content_id),
            "group_id": _string_attr(group_id),
            "owner_user_id": _string_attr(user.user_id),
            "content_format": _string_attr(content_format),
            "created_at": _string_attr(created_at),
        }
        try:
            self._transact_put_new([meta, manifest, index])
        except Exception as original_error:
            self._cleanup_after_failed_commit(document_key, original_error)
            raise
        return self._public_project(meta)

    def list_authoring_projects(
        self,
        auth_subject: str,
        group_id: str,
        content_format: str | None = None,
    ) -> list[dict[str, Any]]:
        if content_format is not None:
            content_format = validate_content_format(content_format)
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :content_prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr(f"GROUP#{group_id}"),
                ":content_prefix": _string_attr("CONTENT#"),
            },
            ConsistentRead=True,
        )
        indexes = self._query_items(response)
        projects: list[dict[str, Any]] = []
        for index in indexes:
            if _item_string(index, "entity") != "authoring_content_index":
                raise RuntimeError("Authoring group content index has an unexpected entity")
            if _item_string(index, "group_id") != group_id:
                raise RuntimeError("Authoring group content index has a mismatched group")
            if _item_string(index, "owner_user_id") != user.user_id:
                continue
            content_id = _item_string(index, "content_id")
            indexed_format = _item_string(index, "content_format")
            if indexed_format == "":
                raise RuntimeError("Authoring group content index has an empty content format")
            if content_format is not None and indexed_format != content_format:
                continue

            meta = self._get_item(pk=f"CONTENT#{content_id}", sk="META")
            if meta is None:
                raise RuntimeError("Authoring group content index points to missing content")
            if _item_string(meta, "group_id") != group_id:
                raise RuntimeError("Indexed Authoring content no longer matches its group")
            if _item_string(meta, "owner_user_id") != user.user_id:
                raise RuntimeError("Indexed Authoring content no longer matches its owner")
            if _item_string(meta, "content_format") != indexed_format:
                raise RuntimeError("Indexed Authoring content format no longer matches metadata")
            projects.append(self._public_project(meta))

        projects.sort(key=lambda project: project["updated_at"], reverse=True)
        return projects

    def _owned_content(
        self,
        auth_subject: str,
        content_id: str,
    ) -> tuple[Any, dict[str, Any]]:
        _validate_content_id(content_id)
        user = self._user_by_auth_subject(auth_subject)
        item = self._get_item(pk=f"CONTENT#{content_id}", sk="META")
        if item is None:
            raise ApiProblem(404, "content_not_found", "Authoring content was not found.")
        group_id = _item_string(item, "group_id")
        self._require_active_membership(user.user_id, group_id)
        if _item_string(item, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "You do not own this Authoring content.")
        status = _item_string(item, "status")
        if status != "draft":
            raise ApiProblem(409, "content_not_editable", "Authoring content is not editable.")
        return user, item
