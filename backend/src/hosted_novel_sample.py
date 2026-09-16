from __future__ import annotations

import io
import zipfile
from typing import Any

from errors import ApiProblem

NOVEL_CONTENT_FORMAT = "minapp/novel@1"
NOVEL_SAMPLE_TITLE = "ひみつの放課後"
NOVEL_SAMPLE_SOURCE_KEY = "hosted/samples/novel/v1/assets.zip"

_SAMPLE_ASSET_MEMBERS = {
    "assets/sample/bg_classroom.png": "bg_classroom.png",
    "assets/sample/bg_rooftop.png": "bg_rooftop.png",
    "assets/sample/ren_normal.png": "ren_normal.png",
}
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def legacy_novel_sample_document() -> dict[str, Any]:
    """Return the text-only sample document shipped before sample assets existed."""
    return {
        "content_format": NOVEL_CONTENT_FORMAT,
        "schema_version": 1,
        "content_revision": 1,
        "title": NOVEL_SAMPLE_TITLE,
        "start_scene": "start",
        "assets": {},
        "characters": {},
        "scenes": {
            "start": {
                "id": "start",
                "events": [
                    {
                        "id": "evt-start-line",
                        "type": "dialogue",
                        "text": "なあ。\n今日、ちょっとだけ寄り道していかない？",
                    },
                    {
                        "id": "evt-start-choice",
                        "type": "choice",
                        "options": [
                            {
                                "id": "ask",
                                "label": "「どうしたの？」",
                                "goto": "rooftop",
                            },
                            {
                                "id": "leave",
                                "label": "「今日は帰るね」",
                                "goto": "leave",
                            },
                        ],
                    },
                ],
            },
            "rooftop": {
                "id": "rooftop",
                "events": [
                    {
                        "id": "evt-rooftop-line",
                        "type": "dialogue",
                        "text": "屋上の空、すごくきれいだったから。\nきみに見せたかったんだ。",
                    },
                    {
                        "id": "evt-rooftop-choice",
                        "type": "choice",
                        "options": [
                            {
                                "id": "sit",
                                "label": "となりに座る",
                                "goto": "together",
                            },
                            {
                                "id": "photo",
                                "label": "空の写真を撮る",
                                "goto": "photo",
                            },
                        ],
                    },
                ],
            },
            "together": {
                "id": "together",
                "events": [
                    {
                        "id": "evt-together-line",
                        "type": "dialogue",
                        "text": "……よかった。\nこの場所、ふたりだけの秘密にしよう。",
                    },
                    {
                        "id": "evt-together-end",
                        "type": "end",
                        "label": "END - ふたりの秘密",
                    },
                ],
            },
            "photo": {
                "id": "photo",
                "events": [
                    {
                        "id": "evt-photo-line",
                        "type": "dialogue",
                        "text": "じゃあ同じ空を持って帰れるね。\n明日も、ここで会おう。",
                    },
                    {
                        "id": "evt-photo-end",
                        "type": "end",
                        "label": "END - 同じ空",
                    },
                ],
            },
            "leave": {
                "id": "leave",
                "events": [
                    {
                        "id": "evt-leave-line",
                        "type": "dialogue",
                        "text": "そっか。じゃあ、また明日。\n次はちゃんと誘うから。",
                    },
                    {
                        "id": "evt-leave-end",
                        "type": "end",
                        "label": "END - また明日",
                    },
                ],
            },
        },
    }


def novel_sample_document() -> dict[str, Any]:
    """Return the editable sample document with backgrounds and a character sprite."""
    return {
        "content_format": NOVEL_CONTENT_FORMAT,
        "schema_version": 1,
        "content_revision": 1,
        "title": NOVEL_SAMPLE_TITLE,
        "start_scene": "start",
        "assets": {
            "bg-classroom": {
                "kind": "image",
                "src": "assets/sample/bg_classroom.png",
                "mime": "image/png",
                "alt": "放課後の教室",
            },
            "bg-rooftop": {
                "kind": "image",
                "src": "assets/sample/bg_rooftop.png",
                "mime": "image/png",
                "alt": "夕暮れの屋上",
            },
            "ren-normal": {
                "kind": "image",
                "src": "assets/sample/ren_normal.png",
                "mime": "image/png",
                "alt": "レン",
            },
        },
        "characters": {
            "ren": {
                "name": "レン",
                "expressions": {"normal": "ren-normal"},
            }
        },
        "scenes": {
            "start": {
                "id": "start",
                "events": [
                    {
                        "id": "evt-start-bg",
                        "type": "background",
                        "asset": "bg-classroom",
                    },
                    {
                        "id": "evt-start-ren",
                        "type": "character",
                        "action": "show",
                        "slot": "center",
                        "character": "ren",
                        "expression": "normal",
                    },
                    {
                        "id": "evt-start-line",
                        "type": "dialogue",
                        "speaker": "ren",
                        "text": "なあ。\n今日、ちょっとだけ寄り道していかない？",
                    },
                    {
                        "id": "evt-start-choice",
                        "type": "choice",
                        "options": [
                            {
                                "id": "ask",
                                "label": "「どうしたの？」",
                                "goto": "rooftop",
                            },
                            {
                                "id": "leave",
                                "label": "「今日は帰るね」",
                                "goto": "leave",
                            },
                        ],
                    },
                ],
            },
            "rooftop": {
                "id": "rooftop",
                "events": [
                    {
                        "id": "evt-rooftop-bg",
                        "type": "background",
                        "asset": "bg-rooftop",
                    },
                    {
                        "id": "evt-rooftop-line",
                        "type": "dialogue",
                        "speaker": "ren",
                        "text": "屋上の空、すごくきれいだったから。\nきみに見せたかったんだ。",
                    },
                    {
                        "id": "evt-rooftop-choice",
                        "type": "choice",
                        "options": [
                            {
                                "id": "sit",
                                "label": "となりに座る",
                                "goto": "together",
                            },
                            {
                                "id": "photo",
                                "label": "空の写真を撮る",
                                "goto": "photo",
                            },
                        ],
                    },
                ],
            },
            "together": {
                "id": "together",
                "events": [
                    {
                        "id": "evt-together-line",
                        "type": "dialogue",
                        "speaker": "ren",
                        "text": "……よかった。\nこの場所、ふたりだけの秘密にしよう。",
                    },
                    {
                        "id": "evt-together-end",
                        "type": "end",
                        "label": "END - ふたりの秘密",
                    },
                ],
            },
            "photo": {
                "id": "photo",
                "events": [
                    {
                        "id": "evt-photo-line",
                        "type": "dialogue",
                        "speaker": "ren",
                        "text": "じゃあ同じ空を持って帰れるね。\n明日も、ここで会おう。",
                    },
                    {
                        "id": "evt-photo-end",
                        "type": "end",
                        "label": "END - 同じ空",
                    },
                ],
            },
            "leave": {
                "id": "leave",
                "events": [
                    {
                        "id": "evt-leave-line",
                        "type": "dialogue",
                        "speaker": "ren",
                        "text": "そっか。じゃあ、また明日。\n次はちゃんと誘うから。",
                    },
                    {
                        "id": "evt-leave-end",
                        "type": "end",
                        "label": "END - また明日",
                    },
                ],
            },
        },
    }


def hydrate_novel_sample_project(
    backend: Any,
    auth_subject: str,
    content_id: str,
) -> dict[str, Any]:
    """Attach bundled sample art to the untouched text-only sample.

    The operation is deliberately conservative: once the user changes the
    sample document or its already-seeded assets, it is treated as user work and
    is never overwritten. A failed partial seed keeps the legacy document valid;
    a later explicit ensure call can continue only when stored bytes still match
    the bundled sample assets.
    """
    project = backend.load_authoring_project(auth_subject, content_id)
    if project.get("content_format") != NOVEL_CONTENT_FORMAT:
        raise ApiProblem(
            409,
            "not_novel_sample",
            "The requested Authoring project is not a Novel sample.",
        )
    document = project.get("document")
    if not isinstance(document, dict):
        raise RuntimeError("Loaded Novel sample has no document object")

    final_document = novel_sample_document()
    if document == final_document:
        return _project_summary(project)

    legacy_document = legacy_novel_sample_document()
    if document != legacy_document:
        if document.get("title") == NOVEL_SAMPLE_TITLE:
            return _project_summary(project)
        raise ApiProblem(
            409,
            "not_novel_sample",
            "The requested Authoring project is not the built-in Novel sample.",
        )

    sample_assets = _sample_asset_bytes(backend)
    asset_paths = _project_asset_paths(project)
    required_paths = set(sample_assets)
    if asset_paths - required_paths:
        return _project_summary(project)

    for path in sorted(asset_paths):
        stored, content_type = backend.get_authoring_asset(
            auth_subject,
            content_id,
            path,
        )
        if content_type != "image/png" or stored != sample_assets[path]:
            return _project_summary(project)

    revision = _positive_revision(project.get("draft_revision"))
    latest = _project_summary(project)
    for path in _SAMPLE_ASSET_MEMBERS:
        if path in asset_paths:
            continue
        latest = backend.save_authoring_asset(
            auth_subject,
            content_id,
            expected_revision=revision,
            path=path,
            data=sample_assets[path],
        )
        revision = _positive_revision(latest.get("draft_revision"))

    latest = backend.save_authoring_document(
        auth_subject,
        content_id,
        expected_revision=revision,
        document=final_document,
    )
    return latest


def _sample_asset_bytes(backend: Any) -> dict[str, bytes]:
    archive_bytes, files, _ = backend._read_zip_object(
        bucket=backend._upload_bucket,
        key=NOVEL_SAMPLE_SOURCE_KEY,
    )
    expected_members = set(_SAMPLE_ASSET_MEMBERS.values())
    if set(files) != expected_members:
        raise RuntimeError("Novel sample asset archive has an unexpected file manifest")

    result: dict[str, bytes] = {}
    with zipfile.ZipFile(io.BytesIO(archive_bytes), "r") as archive:
        for project_path, member in _SAMPLE_ASSET_MEMBERS.items():
            data = archive.read(member)
            if not data.startswith(_PNG_SIGNATURE):
                raise RuntimeError(f"Novel sample asset is not a PNG: {member}")
            result[project_path] = data
    return result


def _project_asset_paths(project: dict[str, Any]) -> set[str]:
    raw_assets = project.get("assets")
    if not isinstance(raw_assets, list):
        raise RuntimeError("Loaded Novel sample assets field is not a list")
    paths: set[str] = set()
    for asset in raw_assets:
        if not isinstance(asset, dict):
            raise RuntimeError("Loaded Novel sample contains a malformed asset entry")
        path = asset.get("path")
        if not isinstance(path, str) or not path:
            raise RuntimeError("Loaded Novel sample asset has an invalid path")
        if path in paths:
            raise RuntimeError("Loaded Novel sample contains duplicate asset paths")
        paths.add(path)
    return paths


def _project_summary(project: dict[str, Any]) -> dict[str, Any]:
    result = dict(project)
    result.pop("document", None)
    return result


def _positive_revision(value: Any) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise RuntimeError("Novel sample returned an invalid draft revision")
    return value
