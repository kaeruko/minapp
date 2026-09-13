from __future__ import annotations

from typing import Any

from aws_backend import _item_string, _string_attr
from errors import ApiProblem
from hosted_catalog_backend import _item_files, _optional_number, _optional_string
from hosted_platform_backend import _now_iso
from hosted_shop_backend import SHOP_VISIBILITIES, HostedShopBackend


class HostedShopManagedBackend(HostedShopBackend):
    """Shop listing policy for Girls group-managed apps."""

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
        group_id = _item_string(app, "group_id")
        membership = self._require_active_membership(user.user_id, group_id)
        app_owner_user_id = _item_string(app, "owner_user_id")
        membership_role = _item_string(membership, "role")
        if user.user_id != app_owner_user_id and membership_role != "owner":
            raise ApiProblem(403, "forbidden", "この作品をショップ掲載する権限がありません。")

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
                        owner_user_id=app_owner_user_id,
                        visibility="listed",
                        listed_at=now,
                    ),
                    self._shop_visibility_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        owner_user_id=app_owner_user_id,
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
                        owner_user_id=app_owner_user_id,
                        visibility="unlisted",
                        listed_at=None,
                    ),
                    self._shop_visibility_update(
                        pk=f"GROUP#{group_id}",
                        sk=f"APP#{app_id}",
                        owner_user_id=app_owner_user_id,
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
