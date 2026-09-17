from __future__ import annotations

import importlib
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch, sentinel

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import hosted_performance_entry


class HostedPerformanceEntryTests(unittest.TestCase):
    def test_provisioned_initialization_prepares_all_list_backends(self):
        with (
            patch.dict(os.environ, {"AWS_LAMBDA_INITIALIZATION_TYPE": "provisioned-concurrency"}),
            patch("hosted_handler._get_backend") as groups,
            patch("hosted_entry._get_backend") as management,
            patch("hosted_authoring_entry._get_backend") as authoring,
            patch("abuse_entry.hosted_lambda_handler") as handler,
        ):
            importlib.reload(hosted_performance_entry)
            groups.assert_called_once_with()
            management.assert_called_once_with()
            authoring.assert_called_once_with()
            handler.assert_not_called()

    def test_on_demand_keeps_lazy_initialization(self):
        with (
            patch.dict(os.environ, {"AWS_LAMBDA_INITIALIZATION_TYPE": "on-demand"}),
            patch("hosted_handler._get_backend") as groups,
            patch("hosted_entry._get_backend") as management,
            patch("hosted_authoring_entry._get_backend") as authoring,
        ):
            importlib.reload(hosted_performance_entry)
            groups.assert_not_called()
            management.assert_not_called()
            authoring.assert_not_called()

    def test_invocations_keep_original_security_and_dispatch(self):
        event = {"rawPath": "/hosted/groups"}
        with patch("abuse_entry.hosted_lambda_handler", return_value=sentinel.response) as handler:
            self.assertIs(
                hosted_performance_entry.lambda_handler(event, sentinel.context),
                sentinel.response,
            )
            handler.assert_called_once_with(event, sentinel.context)
