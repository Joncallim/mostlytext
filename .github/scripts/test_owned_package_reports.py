"""Foundation-free fixture checks for exact-process crash report retention."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("owned", Path(__file__).with_name("run-owned-package-tests.py"))
owned = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owned)


class OwnedReportsTests(unittest.TestCase):
    def test_only_fresh_exact_pid_and_executable_are_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            reports = root / "reports"
            reports.mkdir()
            for name, pid, executable in [("own", 42, "owned-helper"), ("other-pid", 43, "owned-helper"),
                                           ("other-name", 42, "other-helper"), ("stale", 42, "owned-helper")]:
                report = reports / (name + ".ips")
                report.write_text(json.dumps({"app_name": executable}) + "\n" +
                                  json.dumps({"pid": pid, "procPath": "/tmp/" + executable}))
                os.utime(report, (10 if name == "stale" else 30,) * 2)
            (reports / "link.ips").symlink_to(reports / "own.ips")
            (reports / "bad.ips").write_text("not JSON")
            output = root / "output"
            result = owned.collect_reports(reports, output, 42, "owned-helper", 20)
            self.assertEqual([item["name"] for item in result], ["own.ips"])
            self.assertEqual((output / "own.ips").read_bytes(), (reports / "own.ips").read_bytes())

    def test_large_or_nonobject_reports_and_missing_directory_are_ignored(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "large.ips").write_bytes(b"x" * (1024 * 1024 + 1))
            (root / "array.ips").write_text("{}\n[]")
            self.assertEqual(owned.collect_reports(root, root / "output", 42, "helper", 0), [])
            self.assertEqual(owned.collect_reports(root / "missing", root / "output", 42, "helper", 0), [])
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
