from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_builtin_registry import (  # noqa: E402
    CREATIVE_BUILTIN_TEMPLATES,
    merged_builtin_templates,
)


class HostedBuiltinRegistryTests(unittest.TestCase):
    def test_novel_starter_contract(self) -> None:
        template = CREATIVE_BUILTIN_TEMPLATES["novel-starter"]
        self.assertEqual(template["builtin_id"], "novel-starter")
        self.assertEqual(template["version"], 2)
        self.assertEqual(template["title"], "ひみつの放課後")
        self.assertEqual(
            template["asset_path"],
            "assets/builtin/novel_starter/index.html",
        )
        self.assertEqual(
            template["source_key"],
            "hosted/templates/novel-starter/v2/source.zip",
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
        self.assertEqual(set(merged), {"core-demo", "novel-starter"})
        self.assertIsNot(merged["core-demo"], core["core-demo"])
        self.assertIsNot(
            merged["novel-starter"],
            CREATIVE_BUILTIN_TEMPLATES["novel-starter"],
        )

    def test_merge_fails_on_conflicting_id(self) -> None:
        core = {"novel-starter": {"builtin_id": "novel-starter", "version": 999}}
        with self.assertRaisesRegex(RuntimeError, "conflicts with the core catalog"):
            merged_builtin_templates(core)


if __name__ == "__main__":
    unittest.main()
