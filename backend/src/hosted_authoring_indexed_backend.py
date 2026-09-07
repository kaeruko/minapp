from __future__ import annotations

import hashlib
import json
import re
import uuid
from typing import Any

from aws_backend import _aws_error_code, _item_string, _string_attr
from errors import ApiProblem
from hosted_app_management import _visibility
from hosted_authoring_backend import (
    HostedAuthoringBackend,
    _assets_json,
    _document_bytes,
    _validate_content_id,
    validate_content_format,
)
from hosted_catalog_backend import _optional_number
from hosted_platform_backend import _now_iso, _number_attr

_MASTER_DATA_ELEMENT_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.:-]{0,127}$")


def _contract_formats(item: dict[str, Any], field: str) -> tuple[str, ...]:
    raw = item.get(f"{field}_json")
    if raw is None:
        return ()
    if not isinstance(raw, dict) or not isinstance(raw.get("S"), str):
        raise RuntimeError(f"Authoring app {field}_json is not a DynamoDB string")
    try:
        value = json.loads(raw["S"])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Authoring app {field}_json is invalid JSON") from exc
    if (
        not isinstance(value, list)
        or any(not isinstance(content_format, str) for content_format in value)
        or len(set(value)) != len(value)
    ):
        raise RuntimeError(
            f"Authoring app {field}_json must be a unique string list"
        )
    for content_format in value:
        try:
            validate_content_format(content_format)
        except ApiProblem as exc:
            raise RuntimeError(
                f"Authoring app declares an invalid {field} content format"
            ) from exc
    return tuple(value)


def _validate_contract_input(value: Any, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ApiProblem(400, "invalid_authoring_contract", f"{field} must be a string array.")
    if len(set(value)) != len(value):
        raise ApiProblem(400, "invalid_authoring_contract", f"{field} must not contain duplicates.")
    validated: list[str] = []
    for content_format in value:
        validated.append(validate_content_format(content_format))
    return tuple(validated)


class HostedAuthoringIndexedBackend(HostedAuthoringBackend):
    """Authoring storage with explicit group discovery indexes."""

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

    def register_authoring_contract(
        self,
        auth_subject: str,
        group_id: str,
        app_id: str,
        *,
        edits: list[str],
        accepts: list[str],
        master_data_element_id: str | None,
    ) -> dict[str, Any]:
        user, _ = self._require_app_author_access(
            auth_subject,
            group_id,
            app_id,
            editable=True,
        )
        edit_formats = _validate_contract_input(edits, "edits")
        accept_formats = _validate_contract_input(accepts, "accepts")
        if not edit_formats and not accept_formats:
            raise ApiProblem(
                400,
                "invalid_authoring_contract",
                "At least one edits or accepts content format is required.",
            )
        if accept_formats:
            if (
                not isinstance(master_data_element_id, str)
                or _MASTER_DATA_ELEMENT_ID_RE.fullmatch(master_data_element_id) is None
            ):
                raise ApiProblem(
                    400,
                    "invalid_authoring_contract",
                    "Player contracts require a valid master_data_element_id.",
                )
            target_attribute: dict[str, Any] = _string_attr(master_data_element_id)
        else:
            if master_data_element_id is not None:
                raise ApiProblem(
                    400,
                    "invalid_authoring_contract",
                    "master_data_element_id is only valid when accepts is non-empty.",
                )
            target_attribute = {"NULL": True}

        values = {
            ":edits": _string_attr(json.dumps(edit_formats, separators=(",", ":"))),
            ":accepts": _string_attr(json.dumps(accept_formats, separators=(",", ":"))),
            ":target": target_attribute,
            ":editable": {"BOOL": True},
        }
        updates = []
        for pk, sk in (
            (f"APP#{app_id}", "META"),
            (f"GROUP#{group_id}", f"APP#{app_id}"),
        ):
            updates.append(
                {
                    "Update": {
                        "TableName": self._table_name,
                        "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                        "UpdateExpression": (
                            "SET edits_json = :edits, accepts_json = :accepts, "
                            "master_data_element_id = :target"
                        ),
                        "ConditionExpression": (
                            "editable = :editable AND attribute_not_exists(deletion_state)"
                        ),
                        "ExpressionAttributeValues": values,
                    }
                }
            )
        try:
            self._dynamodb.transact_write_items(TransactItems=updates)
        except Exception as exc:
            if _aws_error_code(exc) == "TransactionCanceledException":
                raise ApiProblem(
                    409,
                    "authoring_contract_update_conflict",
                    "The app changed while its Authoring contract was being registered.",
                ) from exc
            raise

        return {
            "app_id": app_id,
            "group_id": group_id,
            "edits": list(edit_formats),
            "accepts": list(accept_formats),
            "master_data_element_id": master_data_element_id,
            "owner_user_id": user.user_id,
        }

    def list_authoring_apps(
        self,
        auth_subject: str,
        group_id: str,
    ) -> list[dict[str, Any]]:
        user = self._user_by_auth_subject(auth_subject)
        self._require_active_membership(user.user_id, group_id)

        apps: list[dict[str, Any]] = []
        for item in self._group_app_items(group_id):
            if _item_string(item, "group_id") != group_id:
                raise RuntimeError("Authoring group app index has a mismatched group")
            deletion_state = item.get("deletion_state", {}).get("S")
            if deletion_state is not None:
                if deletion_state != "deleting":
                    raise RuntimeError("Authoring group app index has an invalid deletion state")
                continue

            edits = _contract_formats(item, "edits")
            accepts = _contract_formats(item, "accepts")
            if not edits and not accepts:
                continue

            source_kind = _item_string(item, "source_kind")
            if source_kind == "builtin":
                pass
            elif source_kind in {"upload", "fork"}:
                if _visibility(item) != "visible":
                    continue
                if _optional_number(item, "published_version") is None:
                    continue
            else:
                raise RuntimeError(
                    f"Authoring app has unsupported source kind: {source_kind!r}"
                )

            apps.append(
                {
                    "app_id": _item_string(item, "app_id"),
                    "group_id": group_id,
                    "title": _item_string(item, "title"),
                    "edits": list(edits),
                    "accepts": list(accepts),
                }
            )

        apps.sort(key=lambda app: (app["title"], app["app_id"]))
        return apps

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
