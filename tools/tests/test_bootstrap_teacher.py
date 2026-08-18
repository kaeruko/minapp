from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from bootstrap_teacher import _new_temporary_password  # noqa: E402


class BootstrapTeacherPasswordTests(unittest.TestCase):
    def test_temporary_password_is_eight_easy_digits(self) -> None:
        for _ in range(100):
            password = _new_temporary_password()
            self.assertIsNotNone(re.fullmatch(r"[2-9]{8}", password))


if __name__ == "__main__":
    unittest.main()
