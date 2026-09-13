from __future__ import annotations

import hashlib
import io
import secrets
import time
import zipfile
from typing import Any
from urllib.parse import quote

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import _item_files, _optional_number, _optional_string
from hosted_platform_backend import _now_iso, _number_attr
from hosted_user_state_backend import HostedUserStateBackend

SHOP_CONTENT_SESSION_SECONDS = 10 * 60
SHOP_CONTENT_TTL_GRACE_SECONDS = 24 * 60 * 60
SHOP_DOWNLOAD_TTL_SECONDS = 10 * 60
SHOP_REPORT_REASONS = frozenset(
    {
        "不適切な表現・内容",
        "嫌がらせ・いじめ",
        "個人情報が含まれている",
        "危険な内容",
        "その他",
    }
)
SHOP_VISIBILITIES = frozenset({"listed", "unlisted"})


def _shop_download_filename(title: str, app_id: str) -> str:
    if not isinstance(title, str) or not title:
        raise ValueError("shop download title must be a non-empty string")
    if not isinstance(app_id, str) or not app_id:
        raise ValueError("shop download app_id must be a non-empty string")
    forbidden = '<>:"/\\|?*'
    sanitized = "".join(
        "_" if char in forbidden or ord(char) < 32 else char
        for char in title
    ).strip().rstrip(". ")
    if not sanitized:
        sanitized = f"minapp-{app_id[:8]}"
    return f"{sanitized}.zip"


def _shop_download_content_disposition(filename: str, app_id: str) -> str:
    ascii_fallback = f"minapp-{app_id}.zip"
    encoded = quote(filename, safe="")
    return (
        f'attachment; filename="{ascii_fallback}"; '
        f"filename*=UTF-8''{encoded}"
    )


class HostedShopBackend(HostedUserStateBackend):
    """Girls shop shared across every Hosted group in this deployment."""

    @staticmethod
    def _shop_visibility(app: dict[str, Any]) -> str:
        value = _optional_string(app, "shop_visibility")
        if value is None:
            return "unlisted"
        if value not in SHOP_VISIBILITIES:
            raise RuntimeError(f"Unsupported stored shop visibility: {value!r}")
        return value

    def _app_meta(self, app_id: str) -> dict[str, Any]:
        item = self._get_item(pk=f"APP#{app_id}", sk="META")
        if item is None:
            raise ApiProblem(404, "shop_app_not_found", "この作品はショップにありません。")
        self._require_not_deleting(item)
        return item

    def _current_shop_app(self, app_id: str) -> dict[str, Any]:
        app = self._app_meta(app_id)
        if self._shop_visibility(app) != "listed":
            raise ApiProblem(404, "shop_app_not_found", "この作品はショップに掲載されていません。")
        version = _optional_number(app, "published_version")
        key = _optional_string(app, "published_key")
        sha256 = _optional_string(app, "published_sha256")
        published_at = _optional_string(app, "published_at")
        if version is None or key is None or sha256 is None or published_at is None:
            raise ApiProblem(409, "app_unpublished", "この作品には公開版がありません。")
        _item_files(app, "published_files_json")
        return app

    def _shop_index_item(self, app: dict[str, Any], listed_at: str) -> dict[str, Any]:
        app_id = _item_string(app, "app_id")
        return {
            "pk": _string_attr("SHOP"),
            "sk": _string_attr(f"APP#{app_id}"),
            "entity": _string_attr("shop_listing"),
            "app_id": _string_attr(app_id),
            "owner_user_id": _string_attr(_item_string(app, "owner_user_id")),
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
        result: list[dict[str, Any]] = []
        for index_item in self._query_items(response):
            if _item_string(index_item, "entity") != "shop_listing":
                raise RuntimeError("SHOP partition contains a non-shop-listing item")
            app_id = _item_string(index_item, "app_id")
            app = self._current_shop_app(app_id)
            if _item_string(index_item, "owner_user_id") != _item_string(app, "owner_user_id"):
                raise RuntimeError("SHOP listing owner does not match app metadata")
            owner = self._user_by_id(_item_string(app, "owner_user_id"))
            published_version = _optional_number(app, "published_version")
            published_at = _optional_string(app, "published_at")
            sha256 = _optional_string(app, "published_sha256")
            if published_version is None or published_at is None or sha256 is None:
                raise RuntimeError("Listed hosted app lost published metadata")
            result.append(
                {
                    "app_id": app_id,
                    "version": str(published_version),
                    "title": _item_string(app, "title"),
                    "owner_user_id": owner.user_id,
                    "owner_display_name": owner.login_id,
                    "published_at": published_at,
                    "sha256": sha256,
                }
            )
        result.sort(key=lambda app: (app["published_at"], app["app_id"]), reverse=True)
        return result

    def set_shop_visibility(
        self,
        auth_subject: str,
        app_id: str,
        visibility: str,
    ) -> dict[str, Any]:
        if visibility not in SHOP_VISIBILITIES:
            raise ApiProblem(400, "invalid_shop_visibility", "visibility must be listed or unlisted.")
        user = self._user_by_auth_subject(auth_subject)
        app = self._app_meta(app_id)
        if _item_string(app, "owner_user_id") != user.user_id:
            raise ApiProblem(403, "forbidden", "この作品をショップ掲載する権限がありません。")
        group_id = _item_string(app, "group_id")
        self._require_active_membership(user.user_id, group_id)
        now = _now_iso()

        if visibility == "listed":
            version = _optional_number(app, "published_version")
            key = _optional_string(app, "published_key")
            sha256 = _optional_string(app, "published_sha256")
            if version is None or key is None or sha256 is None:
                raise ApiProblem(409, "app_unpublished", "公開済みの作品だけショップに掲載できます。")
            _item_files(app, "published_files_json")
            listing = self._shop_index_item(app, now)
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._shop_visibility_update(
                        pk=f"APP#{app_id}",
                        sk="META",
                        owner_user_id=user.user_id,
                        visibility="listed",
                        listed_at=now,
                    ),
                    self._shop_visibility_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        owner_user_id=user.user_id,
                        visibility="listed",
                        listed_at=now,
                    ),
                    {"Put": {"TableName": self._table_name, "Item": listing}},
                ]
            )
        else:
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._shop_visibility_update(
                        pk=f"APP#{app_id}",
                        sk="META",
                        owner_user_id=user.user_id,
                        visibility="unlisted",
                        listed_at=None,
                    ),
                    self._shop_visibility_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        owner_user_id=user.user_id,
                        visibility="unlisted",
                        listed_at=None,
                    ),
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

    def _shop_visibility_update(
        self,
        *,
        pk: str,
        sk: str,
        owner_user_id: str,
        visibility: str,
        listed_at: str | None,
    ) -> dict[str, Any]:
        if visibility == "listed":
            if listed_at is None or not listed_at:
                raise ValueError("listed_at is required when visibility is listed")
            expression = "SET shop_visibility = :visibility, shop_listed_at = :listed_at"
            values = {
                ":visibility": _string_attr(visibility),
                ":listed_at": _string_attr(listed_at),
                ":owner": _string_attr(owner_user_id),
            }
        elif visibility == "unlisted":
            if listed_at is not None:
                raise ValueError("listed_at must be None when visibility is unlisted")
            expression = "SET shop_visibility = :visibility REMOVE shop_listed_at"
            values = {
                ":visibility": _string_attr(visibility),
                ":owner": _string_attr(owner_user_id),
            }
        else:
            raise ValueError(f"unsupported shop visibility: {visibility!r}")
        return {
            "Update": {
                "TableName": self._table_name,
                "Key": {"pk": _string_attr(pk), "sk": _string_attr(sk)},
                "UpdateExpression": expression,
                "ConditionExpression": "owner_user_id = :owner AND attribute_not_exists(deletion_state)",
                "ExpressionAttributeValues": values,
            }
        }

    @staticmethod
    def _assert_version(app: dict[str, Any], version: str) -> int:
        current = _optional_number(app, "published_version")
        if current is None:
            raise ApiProblem(409, "app_unpublished", "この作品には公開版がありません。")
        if version != str(current):
            raise ApiProblem(409, "shop_version_stale", "ショップの作品が更新されました。一覧を更新してください。")
        return current

    def create_shop_launch(self, auth_subject: str, app_id: str, version: str) -> dict[str, Any]:
        user = self._user_by_auth_subject(auth_subject)
        app = self._current_shop_app(app_id)
        published_version = self._assert_version(app, version)
        files = _item_files(app, "published_files_json")
        if "index.html" not in files:
            raise RuntimeError("Listed hosted app has no index.html")
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        expires_at = int(time.time()) + SHOP_CONTENT_SESSION_SECONDS
        item = {
            "pk": _string_attr(f"SHOPCONTENT#{token_hash}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("shop_content_session"),
            "issued_to_user_id": _string_attr(user.user_id),
            "app_id": _string_attr(app_id),
            "published_version": _number_attr(published_version),
            "published_key": _string_attr(_item_string(app, "published_key")),
            "published_sha256": _string_attr(_item_string(app, "published_sha256")),
            "published_files_json": _string_attr(_item_string(app, "published_files_json")),
            "expires_at_epoch": _number_attr(expires_at),
            "ttl_epoch": _number_attr(expires_at + SHOP_CONTENT_TTL_GRACE_SECONDS),
        }
        self._transact_put_new([item])
        return {
            "content_path": f"/shop/content/{token}/index.html",
            "expires_in": SHOP_CONTENT_SESSION_SECONDS,
        }

    def get_shop_file(self, token: str, path: str) -> tuple[bytes, str]:
        if not isinstance(token, str) or not token or len(token) > 128:
            raise ApiProblem(404, "shop_content_not_found", "Shop content was not found.")
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        session = self._get_item(pk=f"SHOPCONTENT#{token_hash}", sk="META")
        if session is None or (_optional_number(session, "expires_at_epoch") or 0) <= int(time.time()):
            raise ApiProblem(404, "shop_content_not_found", "Shop content was not found.")

        app_id = _item_string(session, "app_id")
        self._current_shop_app(app_id)
        normalized = self._normalize_content_path(path)
        expected_files = _item_files(session, "published_files_json")
        if normalized not in expected_files:
            raise ApiProblem(404, "shop_file_not_found", "Shop file was not found.")
        zip_bytes, actual_files, _ = self._read_zip_object(
            bucket=self._published_bucket,
            key=_item_string(session, "published_key"),
            expected_sha256=_item_string(session, "published_sha256"),
        )
        if actual_files != expected_files:
            raise RuntimeError("Shop ZIP manifest does not match session metadata")
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
            try:
                return archive.read(normalized), self._content_type(normalized)
            except KeyError as exc:
                raise ApiProblem(404, "shop_file_not_found", "Shop file was not found.") from exc

    @staticmethod
    def _content_type(path: str) -> str:
        from app_zip import content_type

        return content_type(path)

    def create_shop_download(self, auth_subject: str, app_id: str, version: str) -> dict[str, Any]:
        self._user_by_auth_subject(auth_subject)
        app = self._current_shop_app(app_id)
        self._assert_version(app, version)
        key = _item_string(app, "published_key")
        sha256 = _item_string(app, "published_sha256")
        filename = _shop_download_filename(_item_string(app, "title"), app_id)
        content_disposition = _shop_download_content_disposition(filename, app_id)
        url = self._s3.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": self._published_bucket,
                "Key": key,
                "ResponseContentType": "application/zip",
                "ResponseContentDisposition": content_disposition,
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
        version: str,
        reason: str,
    ) -> dict[str, Any]:
        if reason not in SHOP_REPORT_REASONS:
            raise ApiProblem(400, "invalid_report_reason", "報告理由が不正です。")
        reporter = self._user_by_auth_subject(auth_subject)
        app = self._current_shop_app(app_id)
        published_version = self._assert_version(app, version)
        report_id = secrets.token_hex(16)
        created_at = _now_iso()
        item = {
            "pk": _string_attr(f"REPORT#{report_id}"),
            "sk": _string_attr("META"),
            "entity": _string_attr("ugc_report"),
            "report_id": _string_attr(report_id),
            "app_id": _string_attr(app_id),
            "published_version": _number_attr(published_version),
            "group_id": _string_attr(_item_string(app, "group_id")),
            "reported_owner_user_id": _string_attr(_item_string(app, "owner_user_id")),
            "reported_by_user_id": _string_attr(reporter.user_id),
            "reason": _string_attr(reason),
            "status": _string_attr("open"),
            "source": _string_attr("girls_shop"),
            "created_at": _string_attr(created_at),
        }
        self._transact_put_new([item])
        return {"report_id": report_id, "status": "received", "created_at": created_at}

    def list_group_apps(self, auth_subject: str, group_id: str) -> list[dict[str, Any]]:
        apps = super().list_group_apps(auth_subject, group_id)
        result: list[dict[str, Any]] = []
        for app in apps:
            app_id = app.get("app_id")
            if not isinstance(app_id, str) or not app_id:
                raise RuntimeError("Hosted group app has invalid app_id")
            meta = self._app_meta(app_id)
            enriched = dict(app)
            enriched["shop_visibility"] = self._shop_visibility(meta)
            result.append(enriched)
        return result

    def _delete_hosted_app_authorized(self, group_id: str, app_id: str) -> None:
        app = self._get_item(pk=f"APP#{app_id}", sk="META")
        if app is not None and self._shop_visibility(app) == "listed":
            owner_user_id = _item_string(app, "owner_user_id")
            self._dynamodb.transact_write_items(
                TransactItems=[
                    self._shop_visibility_update(
                        pk=f"APP#{app_id}",
                        sk="META",
                        owner_user_id=owner_user_id,
                        visibility="unlisted",
                        listed_at=None,
                    ),
                    self._shop_visibility_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        owner_user_id=owner_user_id,
                        visibility="unlisted",
                        listed_at=None,
                    ),
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
        super()._delete_hosted_app_authorized(group_id, app_id)
