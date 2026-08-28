from __future__ import annotations

from typing import Any, MutableMapping


# Creative starter apps live separately from the older core demo catalog so the
# starter collection can evolve without coupling its content to catalog logic.
CREATIVE_BUILTIN_TEMPLATES: dict[str, dict[str, Any]] = {
    "novel-starter": {
        "builtin_id": "novel-starter",
        "version": 1,
        "title": "ひみつの放課後",
        "asset_path": "assets/builtin/novel_starter/index.html",
        "source_key": "hosted/templates/novel-starter/v1/source.zip",
    },
}


def register_creative_builtin_templates(
    target: MutableMapping[str, dict[str, Any]],
) -> None:
    """Add creative starters without silently overriding an existing ID."""

    for builtin_id, template in CREATIVE_BUILTIN_TEMPLATES.items():
        existing = target.get(builtin_id)
        if existing is None:
            target[builtin_id] = dict(template)
            continue
        if existing != template:
            raise RuntimeError(
                f"creative builtin {builtin_id!r} conflicts with the core catalog"
            )
