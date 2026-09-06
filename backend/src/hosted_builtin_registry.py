from __future__ import annotations

import re
from typing import Any, Mapping


_CONTENT_FORMAT_RE = re.compile(
    r"^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$"
)
_CONTRACT_FIELDS = ("accepts", "edits")


# Creative starter apps live separately from the older core demo catalog so the
# starter collection can evolve without mutating module-global catalog state.
CREATIVE_BUILTIN_TEMPLATES: dict[str, dict[str, Any]] = {
    "novel-starter": {
        "builtin_id": "novel-starter",
        "version": 4,
        "title": "ひみつの放課後",
        "asset_path": "assets/builtin/novel_starter/index.html",
        "source_key": "hosted/templates/novel-starter/v4/source.zip",
        "accepts": ["minapp/novel@1"],
    },
    "novel-editor": {
        "builtin_id": "novel-editor",
        "version": 1,
        "title": "ノベルゲームメーカー",
        "asset_path": "assets/builtin/novel_editor/index.html",
        "source_key": "hosted/templates/novel-editor/v1/source.zip",
        "edits": ["minapp/novel@1"],
    },
}


def _validated_template_copy(template: Mapping[str, Any]) -> dict[str, Any]:
    copied = dict(template)
    for field in _CONTRACT_FIELDS:
        raw = template.get(field)
        if raw is None:
            continue
        if (
            not isinstance(raw, list)
            or not raw
            or any(not isinstance(item, str) for item in raw)
            or len(set(raw)) != len(raw)
        ):
            raise RuntimeError(
                f"builtin template {template.get('builtin_id')!r} {field} must be a unique non-empty string list"
            )
        for content_format in raw:
            if _CONTENT_FORMAT_RE.fullmatch(content_format) is None:
                raise RuntimeError(
                    f"builtin template {template.get('builtin_id')!r} declares invalid {field} format {content_format!r}"
                )
        copied[field] = list(raw)
    return copied


def merged_builtin_templates(
    core: Mapping[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Return core + creative templates without mutating the caller's mapping."""

    merged = {builtin_id: dict(template) for builtin_id, template in core.items()}
    for builtin_id, template in CREATIVE_BUILTIN_TEMPLATES.items():
        validated = _validated_template_copy(template)
        existing = merged.get(builtin_id)
        if existing is not None and existing != validated:
            raise RuntimeError(
                f"creative builtin {builtin_id!r} conflicts with the core catalog"
            )
        merged[builtin_id] = validated
    return merged
