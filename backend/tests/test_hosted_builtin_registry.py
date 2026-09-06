from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
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
        self.assertEqual(template["master_data_element_id"], "minapp-novel-story")
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
        self.assertNotIn("master_data_element_id", template)

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

        with self.assertRaises(RuntimeError):
            _validated_template_copy(
                {
                    "builtin_id": "bad-target-without-player",
                    "version": 1,
                    "title": "bad",
                    "master_data_element_id": "minapp-master-data",
                }
            )
        with self.assertRaises(RuntimeError):
            _validated_template_copy(
                {
                    "builtin_id": "bad-target",
                    "version": 1,
                    "title": "bad",
                    "accepts": ["minapp/novel@1"],
                    "master_data_element_id": "bad target",
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
