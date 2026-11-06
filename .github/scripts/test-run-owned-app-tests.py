#!/usr/bin/env python3
"""Pure ownership checks; never launch, sample or signal a native application."""
import importlib.util
import os
from pathlib import Path
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("owned_app_probe", Path(__file__).with_name("run-owned-app-tests.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OwnershipTests(unittest.TestCase):
    def test_only_the_exact_same_user_app_born_during_this_command_is_owned(self):
        executable = Path("/tmp/owned/MacDown2.app/Contents/MacOS/MacDown2")
        started = time.time() - 10
        now = time.strftime("%a %b %d %H:%M:%S %Y")
        old = time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(started - 100))
        rows = (f"101 {os.getuid()} {executable}\n102 {os.getuid() + 1} {executable}\n"
                f"103 {os.getuid()} /tmp/other/MacDown2\n104 {os.getuid()} {executable}\n")
        with patch.object(module.subprocess, "check_output", side_effect=[rows, now, old]):
            self.assertEqual([record["pid"] for record in module.owned_apps(executable, started)], [101])

    def test_a_process_that_exits_during_identity_read_is_not_owned(self):
        executable = Path("/tmp/owned/MacDown2")
        rows = f"101 {os.getuid()} {executable}\n"
        failure = module.subprocess.CalledProcessError(1, ["ps"])
        with patch.object(module.subprocess, "check_output", side_effect=[rows, failure]):
            self.assertEqual(module.owned_apps(executable, time.time() - 10), [])

    def test_a_changed_identity_at_the_sampling_edge_is_not_sampled(self):
        executable = Path("/tmp/owned/MacDown2")
        record = {"pid": 101, "birth": "old", "executable": str(executable)}
        with patch.object(module, "owned_apps", side_effect=[[record], []]), \
                patch.object(module.subprocess, "run") as sample:
            self.assertEqual(module.sample_apps(executable, time.time(), Path("/tmp/not-created"), 1), [])
            sample.assert_not_called()


if __name__ == "__main__":
    unittest.main()
