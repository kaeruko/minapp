from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HOSTED_MAIN_TF = REPO_ROOT / "infra" / "hosted" / "main.tf"


class HostedCorsConfigTests(unittest.TestCase):
    def test_authoring_revision_header_is_allowed_by_api_gateway_cors(self) -> None:
        source = HOSTED_MAIN_TF.read_text(encoding="utf-8")
        match = re.search(
            r'resource\s+"aws_apigatewayv2_api"\s+"api"\s*\{.*?'
            r'cors_configuration\s*\{(?P<body>.*?)\n\s*\}',
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, "Hosted API CORS configuration was not found")
        assert match is not None
        cors_body = match.group("body")
        self.assertIn('"authorization"', cors_body)
        self.assertIn('"content-type"', cors_body)
        self.assertIn('"x-minapp-expected-revision"', cors_body)


if __name__ == "__main__":
    unittest.main()
