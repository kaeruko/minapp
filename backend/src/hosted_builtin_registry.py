from __future__ import annotations

from typing import Any, Mapping


# Creative starter apps live separately from the older core demo catalog so the
# starter collection can evolve without mutating module-global catalog state.
CREATIVE_BUILTIN_TEMPLATES: dict[str, dict[str, Any]] = {
    "novel-starter": {
        "builtin_id": "novel-starter",
        "version": 3,
        "title": "ひみつの放課後",
        "asset_path": "assets/builtin/novel_starter/index.html",
        "source_key": "hosted/templates/novel-starter/v3/source.zip",
    },
}


def merged_builtin_templates(
    core: Mapping[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Return core + creative templates without mutating the caller's mapping."""

    merged = {builtin_id: dict(template) for builtin_id, template in core.items()}
    for builtin_id, template in CREATIVE_BUILTIN_TEMPLATES.items():
        existing = merged.get(builtin_id)
        if existing is not None and existing != template:
            raise RuntimeError(
                f"creative builtin {builtin_id!r} conflicts with the core catalog"
            )
        merged[builtin_id] = dict(template)
    return merged
