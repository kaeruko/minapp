from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HOSTED_SOURCES = REPO_ROOT / "infra" / "hosted" / "hosted_sources.tf"


class HostedBuiltinSourcePackagingTests(unittest.TestCase):
    def test_creative_packages_exclude_repository_only_files(self) -> None:
        source = HOSTED_SOURCES.read_text(encoding="utf-8")

        self.assertIn("excludes    = each.value.excludes", source)
        for path in (
            "README.md",
            "test_player_runtime_ready.js",
            "test_story_validator.js",
            "test_asset_tools.js",
            "test_editor_core.js",
            "test_host_authoring_roundtrip.py",
        ):
            self.assertIn(f'"{path}"', source)


if __name__ == "__main__":
    unittest.main()
