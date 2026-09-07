from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

from errors import ApiProblem  # noqa: E402
from hosted_authoring_web_bridge import inject_web_bridge  # noqa: E402


class HostedAuthoringWebBridgeOrderTests(unittest.TestCase):
    def test_bridge_is_installed_before_editor_startup_script(self) -> None:
        source = b"""<!doctype html>
<html lang=\"ja\">
<head><meta charset=\"utf-8\"></head>
<body>
<script src=\"story-validator.js\"></script>
<script>window.editorSawMinapp = window.minapp !== undefined;</script>
</body>
</html>"""
        injected = inject_web_bridge(
            source,
            parent_origin="https://portal.example.test",
            bridge_nonce="n" * 43,
        ).decode("utf-8")

        self.assertTrue(injected.startswith("<!doctype html>"))
        self.assertEqual(injected.count('data-minapp-web-bridge="1"'), 1)
        self.assertLess(
            injected.index('data-minapp-web-bridge="1"'),
            injected.index('<script src="story-validator.js">'),
        )
        self.assertLess(
            injected.index("Object.defineProperty(window, 'minapp'"),
            injected.index("window.editorSawMinapp"),
        )

    def test_inert_script_does_not_capture_bridge_insertion(self) -> None:
        source = b"""<!doctype html>
<html><body>
<template><script>window.templateOnly = true;</script></template>
<noscript><script>window.noScriptOnly = true;</script></noscript>
<script>window.editorStarts = true;</script>
</body></html>"""
        injected = inject_web_bridge(
            source,
            parent_origin="https://portal.example.test",
            bridge_nonce="n" * 43,
        ).decode("utf-8")

        marker = injected.index('data-minapp-web-bridge="1"')
        self.assertGreater(marker, injected.index("window.noScriptOnly"))
        self.assertLess(marker, injected.index("window.editorStarts"))

    def test_web_editor_without_active_script_fails_explicitly(self) -> None:
        with self.assertRaises(ApiProblem) as caught:
            inject_web_bridge(
                b"<!doctype html><html><body><p>No editor script</p></body></html>",
                parent_origin="https://portal.example.test",
                bridge_nonce="n" * 43,
            )
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(caught.exception.error, "authoring_editor_web_incompatible")
        self.assertIn("active script tag", caught.exception.message)


if __name__ == "__main__":
    unittest.main()
