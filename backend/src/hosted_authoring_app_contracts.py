from __future__ import annotations

from typing import Any, Callable

from aws_backend import _item_string
from errors import ApiProblem
from hosted_authoring_preview import _player_formats
from hosted_authoring_session import _editor_formats

_FormatReader = Callable[[dict[str, Any]], tuple[str, ...]]


def _optional_formats(
    item: dict[str, Any],
    reader: _FormatReader,
    *,
    missing_error: str,
) -> tuple[str, ...]:
    try:
        return reader(item)
    except ApiProblem as exc:
        if exc.error == missing_error:
            return ()
        raise


def list_authoring_app_contracts(
    backend: Any,
    auth_subject: str,
    group_id: str,
) -> list[dict[str, Any]]:
    """Return installed Editor/Player compatibility contracts for one group.

    This intentionally exposes only compatibility metadata needed by the
    trusted Host. Source keys, credentials, capability tokens, and owner ids
    are not part of this response.
    """

    user = backend._user_by_auth_subject(auth_subject)
    backend._require_active_membership(user.user_id, group_id)

    contracts: list[dict[str, Any]] = []
    for item in backend._group_app_items(group_id):
        if _item_string(item, "group_id") != group_id:
            raise RuntimeError("Authoring app index has a mismatched group")

        deletion_state = item.get("deletion_state", {}).get("S")
        if deletion_state is not None:
            if deletion_state == "deleting":
                continue
            raise RuntimeError("Authoring app index has an unsupported deletion state")

        edits = _optional_formats(
            item,
            _editor_formats,
            missing_error="editor_not_authoring_capable",
        )
        accepts = _optional_formats(
            item,
            _player_formats,
            missing_error="player_not_authoring_capable",
        )
        if not edits and not accepts:
            continue

        contracts.append(
            {
                "app_id": _item_string(item, "app_id"),
                "group_id": group_id,
                "title": _item_string(item, "title"),
                "edits": list(edits),
                "accepts": list(accepts),
            }
        )

    contracts.sort(key=lambda app: (app["title"], app["app_id"]))
    return contracts
