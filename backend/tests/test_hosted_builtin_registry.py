from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
REPO_ROOT = Path(__file__).resolve().parents[2]
NOVEL_STARTER_DIR = REPO_ROOT / "apps" / "mobile" / "assets" / "builtin" / "novel_starter"
NOVEL_EDITOR_DIR = REPO_ROOT / "apps" / "mobile" / "assets" / "builtin" / "novel_editor"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_builtin_registry import (  # noqa: E402
    CREATIVE_BUILTIN_TEMPLATES,
    _validated_template_copy,
    merged_builtin_templates,
)


class HostedBuiltinRegistryTests(unittest.TestCase):
    def test_novel_starter_contract(self) -> None:
        template = CREATIVE_BUILTIN_TEMPLATES["novel-starter"]
        self.assertEqual(template["builtin_id"], "novel-starter")
        self.assertEqual(template["version"], 4)
        self.assertEqual(template["title"], "ひみつの放課後")
        self.assertEqual(
            template["asset_path"],
            "assets/builtin/novel_starter/index.html",
        )
        self.assertEqual(
            template["source_key"],
            "hosted/templates/novel-starter/v4/source.zip",
        )
        self.assertEqual(template["accepts"], ["minapp/novel@1"])
        self.assertNotIn("edits", template)

    def test_novel_editor_contract(self) -> None:
        template = CREATIVE_BUILTIN_TEMPLATES["novel-editor"]
        self.assertEqual(template["builtin_id"], "novel-editor")
        self.assertEqual(template["version"], 1)
        self.assertEqual(template["title"], "ノベルゲームメーカー")
        self.assertEqual(
            template["asset_path"],
            "assets/builtin/novel_editor/index.html",
        )
        self.assertEqual(
            template["source_key"],
            "hosted/templates/novel-editor/v1/source.zip",
        )
        self.assertEqual(template["edits"], ["minapp/novel@1"])
        self.assertNotIn("accepts", template)

    def test_novel_starter_v4_bundles_json_player_runtime(self) -> None:
        index = (NOVEL_STARTER_DIR / "index.html").read_text(encoding="utf-8")
        player = (NOVEL_STARTER_DIR / "player.js").read_text(encoding="utf-8")
        validator = (NOVEL_STARTER_DIR / "story-validator.js").read_text(encoding="utf-8")

        self.assertIn('id="minapp-novel-story"', index)
        self.assertIn('<script src="story-validator.js"></script>', index)
        self.assertIn('<script src="player.js"></script>', index)
        self.assertIn("const FORMAT = 'minapp/novel@1';", validator)
        self.assertIn("window.addEventListener('minappready', onMinAppReady);", player)
        self.assertIn("window.minapp.userState", player)
        self.assertNotIn("window.minapp.state", player)

    def test_novel_editor_v1_bundles_shared_format_and_authoring_bridge(self) -> None:
        index = (NOVEL_EDITOR_DIR / "index.html").read_text(encoding="utf-8")
        editor = (NOVEL_EDITOR_DIR / "editor.js").read_text(encoding="utf-8")
        core = (NOVEL_EDITOR_DIR / "editor-core.js").read_text(encoding="utf-8")
        editor_validator = (NOVEL_EDITOR_DIR / "story-validator.js").read_text(encoding="utf-8")
        player_validator = (NOVEL_STARTER_DIR / "story-validator.js").read_text(encoding="utf-8")

        self.assertEqual(editor_validator, player_validator)
        self.assertIn('<script src="story-validator.js"></script>', index)
        self.assertIn('<script src="editor-core.js"></script>', index)
        self.assertIn('<script src="editor.js"></script>', index)
        self.assertIn("const FORMAT = 'minapp/novel@1';", core)
        self.assertIn("minapp.authoring", editor)
        self.assertIn("api.load()", editor)
        self.assertIn("api.save(documentToSave, { expectedRevision })", editor)
        self.assertIn("api.publish({ expectedRevision })", editor)
        self.assertIn("window.addEventListener('minappready', initializeFromHost);", editor)
        self.assertNotIn("window.minapp.state", editor)
        self.assertNotIn("window.minapp.userState", editor)

    def test_contract_validation_fails_closed(self) -> None:
        for field, value in (
            ("edits", []),
            ("edits", ["minapp/novel@1", "minapp/novel@1"]),
            ("edits", ["novel-v1"]),
            ("accepts", ["minapp/novel@0"]),
            ("accepts", "minapp/novel@1"),
        ):
            with self.subTest(field=field, value=value):
                with self.assertRaises(RuntimeError):
                    _validated_template_copy(
                        {
                            "builtin_id": "bad-template",
                            "version": 1,
                            "title": "bad",
                            field: value,
                        }
                    )

    def test_merge_keeps_input_unchanged_and_returns_copies(self) -> None:
        core = {
            "core-demo": {
                "builtin_id": "core-demo",
                "version": 1,
                "title": "core",
            }
        }
        before = {key: dict(value) for key, value in core.items()}

        merged = merged_builtin_templates(core)

        self.assertEqual(core, before)
        self.assertEqual(set(merged), {"core-demo", "novel-starter", "novel-editor"})
        self.assertIsNot(merged["core-demo"], core["core-demo"])
        self.assertIsNot(
            merged["novel-starter"],
            CREATIVE_BUILTIN_TEMPLATES["novel-starter"],
        )
        self.assertIsNot(
            merged["novel-editor"],
            CREATIVE_BUILTIN_TEMPLATES["novel-editor"],
        )
        self.assertIsNot(
            merged["novel-editor"]["edits"],
            CREATIVE_BUILTIN_TEMPLATES["novel-editor"]["edits"],
        )

    def test_merge_fails_on_conflicting_id(self) -> None:
        core = {"novel-starter": {"builtin_id": "novel-starter", "version": 999}}
        with self.assertRaisesRegex(RuntimeError, "conflicts with the core catalog"):
            merged_builtin_templates(core)


if __name__ == "__main__":
    unittest.main()
