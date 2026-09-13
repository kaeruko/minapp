from __future__ import annotations

import secrets
import time
from typing import Any

from aws_backend import _item_string, _string_attr
from display_name_backend import DisplayNameAwsBackend
from errors import ApiProblem
from phase2_backend import _now_iso
from phase3_backend import LAUNCH_TTL_SECONDS, REPORT_REASONS

SHOP_DOWNLOAD_TTL_SECONDS = 10 * 60
SHOP_VISIBILITIES = frozenset({"listed", "unlisted"})


class ShopAwsBackend(DisplayNameAwsBackend):
    """Cross-group shop rules layered on the classroom backend.

    SHOP items are deliberately only an index of listed app ids. Publication
    metadata is resolved from APP/VERSION records for every read/action so a
    stale denormalized version can never be launched or downloaded.
    """

    @staticmethod
    def _shop_visibility(meta: dict[str, Any]) -> str:
        raw = meta.get("shop_visibility")
        if raw is None:
            return "unlisted"
        value = _item_string(meta, "shop_visibility")
        if value not in SHOP_VISIBILITIES:
            raise RuntimeError(f"Unsupported stored shop visibility: {value!r}")
        return value

    def _current_shop_version(self, app_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        meta = self._require_active_app(app_id)
        if self._shop_visibility(meta) != "listed":
            raise ApiProblem(404, "shop_app_not_found", "この作品はショップに掲載されていません。")

        latest = self._latest_publication_decision(self._version_items(app_id))
        if latest is None:
            raise ApiProblem(409, "app_not_published", "この作品には公開版がありません。")
        status = _item_string(latest, "status")
        if status == "unpublished":
            raise ApiProblem(409, "app_unpublished", "この作品は公開停止中です。")
        if status != "approved":
            raise RuntimeError(f"Unsupported publication decision: {status!r}")
        _item_string(latest, "published_key")
        _item_string(latest, "sha256")
        return meta, latest

    def _shop_listing_item(self, meta: dict[str, Any], listed_at: str) -> dict[str, Any]:
        app_id = _item_string(meta, "app_id")
        return {
            "pk": _string_attr("SHOP"),
            "sk": _string_attr(f"APP#{app_id}"),
            "entity": _string_attr("shop_listing"),
            "app_id": _string_attr(app_id),
            "owner_user_id": _string_attr(_item_string(meta, "owner_user_id")),
            "listed_at": _string_attr(listed_at),
        }

    def list_shop_apps(self, auth_subject: str) -> list[dict[str, Any]]:
        self._user_by_auth_subject(auth_subject)
        response = self._dynamodb.query(
            TableName=self._table_name,
            KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
            ExpressionAttributeValues={
                ":pk": _string_attr("SHOP"),
                ":prefix": _string_attr("APP#"),
            },
            ConsistentRead=True,
        )

        apps: list[dict[str, Any]] = []
        for index_item in self._query_items(response):
            if _item_string(index_item, "entity") != "shop_listing":
                raise RuntimeError("SHOP partition contains a non-shop-listing item")
            app_id = _item_string(index_item, "app_id")
            meta, version = self._current_shop_version(app_id)
            if _item_string(meta, "owner_user_id") != _item_string(index_item, "owner_user_id"):
                raise RuntimeError("SHOP listing owner does not match app metadata")

            payload = self._mobile_public_version(version)
            payload = self._decorate_app_owner(payload)
            payload.pop("group_name", None)
            payload["sha256"] = _item_string(version, "sha256")
            apps.append(payload)

        apps.sort(
            key=lambda item: (item["reviewed_at"], item["created_at"], item["app_id"]),
            reverse=True,
        )
        return apps

    def set_shop_visibility(
        self,
        auth_subject: str,
        app_id: str,
        visibility: str,
    ) -> dict[str, Any]:
        if visibility not in SHOP_VISIBILITIES:
            raise ApiProblem(400, "invalid_shop_visibility", "visibility must be listed or unlisted.")

        user = self._user_by_auth_subject(auth_subject)
        meta = self._require_active_app(app_id)
        if _item_string(meta, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "この作品をショップ掲載する権限がありません。")

        listed_at = _now_iso()
        if visibility == "listed":
            self._current_public_version_without_visibility(app_id)
            listing = self._shop_listing_item(meta, listed_at)
            self._dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"APP#{app_id}"),
                                "sk": _string_attr("META"),
                            },
                            "UpdateExpression": "SET shop_visibility = :listed, shop_listed_at = :listed_at, shop_listed_by = :user_id",
                            "ConditionExpression": "owner_user_id = :user_id AND (attribute_not_exists(#app_status) OR #app_status = :active)",
                            "ExpressionAttributeNames": {"#app_status": "status"},
                            "ExpressionAttributeValues": {
                                ":listed": _string_attr("listed"),
                                ":listed_at": _string_attr(listed_at),
                                ":user_id": _string_attr(user.user_id),
                                ":active": _string_attr("active"),
                            },
                        }
                    },
                    {
                        "Put": {
                            "TableName": self._table_name,
                            "Item": listing,
                        }
                    },
                ]
            )
        else:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr(f"APP#{app_id}"),
                                "sk": _string_attr("META"),
                            },
                            "UpdateExpression": "SET shop_visibility = :unlisted REMOVE shop_listed_at, shop_listed_by",
                            "ConditionExpression": "owner_user_id = :user_id AND (attribute_not_exists(#app_status) OR #app_status = :active)",
                            "ExpressionAttributeNames": {"#app_status": "status"},
                            "ExpressionAttributeValues": {
                                ":unlisted": _string_attr("unlisted"),
                                ":user_id": _string_attr(user.user_id),
                                ":active": _string_attr("active"),
                            },
                        }
                    },
                    {
                        "Delete": {
                            "TableName": self._table_name,
                            "Key": {
                                "pk": _string_attr("SHOP"),
                                "sk": _string_attr(f"APP#{app_id}"),
                            },
                        }
                    },
                ]
            )
        return {"app_id": app_id, "shop_visibility": visibility}

    def _current_public_version_without_visibility(self, app_id: str) -> dict[str, Any]:
        self._require_active_app(app_id)
        latest = self._latest_publication_decision(self._version_items(app_id))
        if latest is None:
            raise ApiProblem(409, "app_not_published", "公開済みの作品だけショップに掲載できます。")
        status = _item_string(latest, "status")
        if status == "unpublished":
            raise ApiProblem(409, "app_unpublished", "公開停止中の作品はショップに掲載できません。")
        if status != "approved":
            raise RuntimeError(f"Unsupported publication decision: {status!r}")
        _item_string(latest, "published_key")
        _item_string(latest, "sha256")
        return latest

    def create_shop_launch(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        _, version = self._current_shop_version(app_id)
        if _item_string(version, "version_id") != version_id:
            raise ApiProblem(409, "shop_version_stale", "ショップの作品が更新されました。一覧を更新してください。")

        token = secrets.token_urlsafe(32)
        expires_at = int(time.time()) + LAUNCH_TTL_SECONDS
        item = {
            "pk": _string_attr(f"LAUNCH#{token}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("launch_token"),
            "published_key": _string_attr(_item_string(version, "published_key")),
            "sha256": _string_attr(_item_string(version, "sha256")),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(_item_string(version, "group_id")),
            "issued_to_user_id": _string_attr(user.user_id),
            "expires_at": {"N": str(expires_at)},
        }
        self._transact_put_new([item])
        return {
            "content_path": f"/launch/{token}/index.html",
            "expires_in": LAUNCH_TTL_SECONDS,
        }

    def create_shop_download(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        self._user_by_auth_subject(auth_subject)
        _, version = self._current_shop_version(app_id)
        if _item_string(version, "version_id") != version_id:
            raise ApiProblem(409, "shop_version_stale", "ショップの作品が更新されました。一覧を更新してください。")
        key = _item_string(version, "published_key")
        sha256 = _item_string(version, "sha256")
        filename = _item_string(version, "filename")
        url = self._s3.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": self._published_bucket,
                "Key": key,
                "ResponseContentType": "application/zip",
                "ResponseContentDisposition": f'attachment; filename="{app_id}.zip"',
            },
            ExpiresIn=SHOP_DOWNLOAD_TTL_SECONDS,
        )
        if not isinstance(url, str) or not url.startswith("https://"):
            raise RuntimeError("S3 did not return an HTTPS presigned URL")
        return {
            "url": url,
            "filename": filename,
            "sha256": sha256,
            "expires_in": SHOP_DOWNLOAD_TTL_SECONDS,
        }

    def create_shop_report(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
        reason: str,
    ) -> dict[str, Any]:
        if reason not in REPORT_REASONS:
            raise ApiProblem(400, "invalid_report_reason", "報告理由が不正です。")
        reporter = self._user_by_auth_subject(auth_subject)
        _, version = self._current_shop_version(app_id)
        if _item_string(version, "version_id") != version_id:
            raise ApiProblem(409, "shop_version_stale", "ショップの作品が更新されました。一覧を更新してください。")

        report_id = secrets.token_hex(16)
        created_at = _now_iso()
        item = {
            "pk": _string_attr(f"REPORT#{report_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("ugc_report"),
            "report_id": _string_attr(report_id),
            "app_id": _string_attr(app_id),
            "version_id": _string_attr(version_id),
            "group_id": _string_attr(_item_string(version, "group_id")),
            "reported_owner_user_id": _string_attr(_item_string(version, "owner_user_id")),
            "reported_by_user_id": _string_attr(reporter.user_id),
            "reason": _string_attr(reason),
            "status": _string_attr("open"),
            "source": _string_attr("shop"),
            "created_at": _string_attr(created_at),
        }
        self._transact_put_new([item])
        return {"report_id": report_id, "status": "received", "created_at": created_at}

    def unpublish_app(
        self,
        auth_subject: str,
        app_id: str,
        version_id: str,
    ) -> dict[str, Any]:
        self._require_active_app(app_id)
        teacher = self._user_by_auth_subject(auth_subject)
        version = self._version_item(app_id, version_id)
        group_id = _item_string(version, "group_id")
        self._require_teacher_membership(teacher.user_id, group_id)
        if _item_string(version, "status") != "approved":
            raise ApiProblem(409, "app_not_published", "現在公開中の作品だけ公開を停止できます。")

        latest = self._latest_publication_decision(self._version_items(app_id))
        if latest is None:
            raise RuntimeError("Approved app has no publication decision")
        latest_status = _item_string(latest, "status")
        if latest_status != "approved":
            if latest_status == "unpublished":
                raise ApiProblem(409, "app_not_published", "この作品はすでに公開停止中です。")
            raise RuntimeError(f"Unsupported publication decision: {latest_status!r}")
        if _item_string(latest, "version_id") != version_id:
            raise ApiProblem(
                409,
                "old_version_not_published",
                "この作品には新しい公開版があります。一覧を更新してください。",
            )

        owner_user_id = _item_string(version, "owner_user_id")
        unpublished_at = _now_iso()
        version_keys = [
            (f"APP#{app_id}", f"VERSION#{version_id}"),
            (f"GROUP#{group_id}", f"APP#{app_id}#VERSION#{version_id}"),
            (f"USER#{owner_user_id}", f"APP#{app_id}#VERSION#{version_id}"),
        ]
        self._dynamodb.transact_write_items(
            TransactItems=[
                *[
                    {
                        "Update": {
                            "TableName": self._table_name,
                            "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                            "UpdateExpression": "SET #status = :unpublished, unpublished_at = :at, unpublished_by = :by",
                            "ConditionExpression": "#status = :approved",
                            "ExpressionAttributeNames": {"#status": "status"},
                            "ExpressionAttributeValues": {
                                ":approved": _string_attr("approved"),
                                ":unpublished": _string_attr("unpublished"),
                                ":at": _string_attr(unpublished_at),
                                ":by": _string_attr(teacher.user_id),
                            },
                        }
                    }
                    for pk, sk in version_keys
                ],
                {
                    "Update": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"APP#{app_id}"),
                            "sk": _string_attr("META"),
                        },
                        "UpdateExpression": "SET shop_visibility = :unlisted REMOVE shop_listed_at, shop_listed_by",
                        "ConditionExpression": "attribute_exists(pk) AND (attribute_not_exists(#app_status) OR #app_status = :active)",
                        "ExpressionAttributeNames": {"#app_status": "status"},
                        "ExpressionAttributeValues": {
                            ":unlisted": _string_attr("unlisted"),
                            ":active": _string_attr("active"),
                        },
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr("SHOP"),
                            "sk": _string_attr(f"APP#{app_id}"),
                        },
                    }
                },
            ]
        )
        version["status"] = _string_attr("unpublished")
        version["unpublished_at"] = _string_attr(unpublished_at)
        version["unpublished_by"] = _string_attr(teacher.user_id)
        return self._public_version(version)

    def archive_app(self, auth_subject: str, app_id: str) -> None:
        student = self._user_by_auth_subject(auth_subject)
        self._require_role(student, "student")
        meta = self._require_active_app(app_id)
        if _item_string(meta, "owner_user_id") != student.user_id:
            raise ApiProblem(403, "forbidden", "この作品を削除する権限がありません。")
        group_id = _item_string(meta, "group_id")
        self._require_active_membership(student.user_id, group_id, "student")
        versions = self._version_items(app_id)
        if any(_item_string(item, "status") == "pending_review" for item in versions):
            raise ApiProblem(
                409,
                "review_in_progress",
                "先生の確認待ちの版があるため削除できません。確認が終わってから削除してください。",
            )

        archived_at = _now_iso()
        self._dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr(f"APP#{app_id}"),
                            "sk": _string_attr("META"),
                        },
                        "UpdateExpression": "SET #status = :archived, archived_at = :archived_at, shop_visibility = :unlisted REMOVE shop_listed_at, shop_listed_by",
                        "ConditionExpression": "owner_user_id = :owner AND (attribute_not_exists(#status) OR #status = :active)",
                        "ExpressionAttributeNames": {"#status": "status"},
                        "ExpressionAttributeValues": {
                            ":owner": _string_attr(student.user_id),
                            ":active": _string_attr("active"),
                            ":archived": _string_attr("archived"),
                            ":archived_at": _string_attr(archived_at),
                            ":unlisted": _string_attr("unlisted"),
                        },
                    }
                },
                {
                    "Delete": {
                        "TableName": self._table_name,
                        "Key": {
                            "pk": _string_attr("SHOP"),
                            "sk": _string_attr(f"APP#{app_id}"),
                        },
                    }
                },
            ]
        )
