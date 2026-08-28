from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from hosted_builtin_registry import (  # noqa: E402
    CREATIVE_BUILTIN_TEMPLATES,
    register_creative_builtin_templates,
)


class HostedBuiltinRegistryTests(unittest.TestCase):
    def test_novel_starter_contract(self) -> None:
        template = CREATIVE_BUILTIN_TEMPLATES["novel-starter"]
        self.assertEqual(template["builtin_id"], "novel-starter")
        self.assertEqual(template["version"], 1)
        self.assertEqual(template["title"], "ひみつの放課後")
        self.assertEqual(
            template["asset_path"],
            "assets/builtin/novel_starter/index.html",
        )
        self.assertEqual(
            template["source_key"],
            "hosted/templates/novel-starter/v1/source.zip",
        )

    def test_registration_is_idempotent_and_does_not_alias_template(self) -> None:
        target: dict[str, dict[str, object]] = {}
        register_creative_builtin_templates(target)
        register_creative_builtin_templates(target)

        self.assertEqual(set(target), {"novel-starter"})
        self.assertEqual(target["novel-starter"], CREATIVE_BUILTIN_TEMPLATES["novel-starter"])
        self.assertIsNot(target["novel-starter"], CREATIVE_BUILTIN_TEMPLATES["novel-starter"])

    def test_registration_fails_on_conflicting_id(self) -> None:
        target = {"novel-starter": {"builtin_id": "novel-starter", "version": 999}}
        with self.assertRaisesRegex(RuntimeError, "conflicts with the core catalog"):
            register_creative_builtin_templates(target)


if __name__ == "__main__":
    unittest.main()
