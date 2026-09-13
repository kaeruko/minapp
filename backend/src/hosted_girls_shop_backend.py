from __future__ import annotations

from typing import Any

from hosted_shop_managed_backend import HostedShopManagedBackend
from hosted_shop_runtime_backend import HostedShopRuntimeBackend
from hosted_user_state_backend import HostedUserStateBackend


class HostedGirlsShopBackend(HostedShopRuntimeBackend, HostedShopManagedBackend):
    """Final Girls shop backend: cross-group catalog, managed listing, isolated Runtime."""

    def list_group_apps(
        self, auth_subject: str, group_id: str
    ) -> list[dict[str, Any]]:
        # The shop is additive. Do not inject shop-only fields into the existing
        # group-app response contract consumed throughout Girls.
        return HostedUserStateBackend.list_group_apps(self, auth_subject, group_id)

    def delete_hosted_app(
        self, auth_subject: str, group_id: str, app_id: str
    ) -> None:
        # Authorize before touching the shop Runtime namespace. The ordinary
        # Hosted deletion performs the same authorization again before deleting
        # canonical source/published metadata.
        self._require_app_management_access(
            auth_subject,
            group_id,
            app_id,
            editable=False,
        )
        shop_group_id = self._shop_runtime_group_id(app_id)
        shared_items = self._runtime_items(shop_group_id, app_id)
        if shared_items:
            self._runtime_dynamodb.transact_write_items(
                TransactItems=[
                    {
                        "Delete": {
                            "TableName": self._runtime_table_name,
                            "Key": {"pk": item["pk"], "sk": item["sk"]},
                            "ConditionExpression": "attribute_exists(pk)",
                        }
                    }
                    for item in shared_items
                ]
            )
        self._delete_all_runtime_user_state(shop_group_id, app_id)
        super().delete_hosted_app(auth_subject, group_id, app_id)
