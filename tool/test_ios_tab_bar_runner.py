import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import run_ios_tab_bar_smoke as runner


class FinishedProcess:
    returncode = 0

    def poll(self):
        return self.returncode


class TabBarRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.data = self.root / "app"
        (self.data / "Documents").mkdir(parents=True)
        self.output = self.root / "results"
        self.status = self.data / "Documents/native-tab-bar-status.json"
        self.image = self.data / "Documents/native-tab-bar.png"
        self.launches = 0

    def run_case(self, results):
        def launch(*args, **kwargs):
            phase, png = results[self.launches]
            self.launches += 1
            if phase:
                self.status.write_text(json.dumps({"phase": phase, "detail": "fixture"}), encoding="utf-8")
            if png:
                self.image.write_bytes(runner.PNG_HEADER + b"fixture")
            return FinishedProcess()
        with patch.object(runner.subprocess, "Popen", side_effect=launch), \
                patch.object(runner.subprocess, "run"), \
                contextlib.redirect_stdout(io.StringIO()):
            runner.run_check("device", self.data, self.output, grace=0)

    def test_result_and_screenshot_pass_without_console_marker(self):
        self.run_case([("passed", True)])
        self.assertEqual(self.launches, 1)
        self.assertTrue((self.output / self.status.name).exists())
        self.assertTrue((self.output / self.image.name).exists())

    def test_no_app_entry_retries_once(self):
        self.run_case([(None, False), ("passed", True)])
        self.assertEqual(self.launches, 2)

    def test_assertion_failure_never_retries(self):
        with self.assertRaisesRegex(RuntimeError, "assertion failed"):
            self.run_case([("failed", False)])
        self.assertEqual(self.launches, 1)
        self.assertTrue((self.output / "status-1.json").exists())

    def test_exit_after_app_entry_is_failure(self):
        with self.assertRaisesRegex(RuntimeError, "did not finish"):
            self.run_case([("launched", False)])
        self.assertEqual(self.launches, 1)

    def test_passing_marker_without_screenshot_fails(self):
        with self.assertRaisesRegex(RuntimeError, "valid screenshot"):
            self.run_case([("passed", False)])

    def test_stale_success_cannot_satisfy_this_run(self):
        self.status.write_text('{"phase":"passed"}', encoding="utf-8")
        self.image.write_bytes(runner.PNG_HEADER)
        with self.assertRaisesRegex(RuntimeError, "did not finish"):
            self.run_case([(None, False), (None, False)])
        self.assertEqual(self.launches, 2)


if __name__ == "__main__":
    unittest.main()
