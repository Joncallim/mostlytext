"""Foundation-free fixture checks for exact-process crash report retention."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

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

    def test_sample_refuses_a_different_process_before_attaching(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            host = output / "owned-helper"
            host.write_bytes(b"helper")
            process = mock.Mock(pid=42)
            process.poll.return_value = None
            with mock.patch.object(owned.subprocess, "check_output", return_value="999 /tmp/other-helper\n"), \
                    mock.patch.object(owned.subprocess, "run") as sample:
                record = owned.sample_host(process, host, output, "timeout")
            self.assertEqual(record["sample_refused"], "owned helper identity unavailable")
            sample.assert_not_called()

    def test_sample_retains_only_exact_owned_helper_stack(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            host = output / "owned-helper"
            host.write_bytes(b"helper")
            process = mock.Mock(pid=42)
            process.poll.return_value = None
            sample_bytes = b"owned stack\n"

            def write_sample(command, **_kwargs):
                Path(command[command.index("-file") + 1]).write_bytes(sample_bytes)
                return mock.Mock(returncode=0)

            with mock.patch.object(owned.subprocess, "check_output",
                                   return_value=f"{os.getuid()} {host}\n"), \
                    mock.patch.object(owned.subprocess, "run", side_effect=write_sample):
                record = owned.sample_host(process, host, output, "timeout")
            self.assertEqual(record["sample_sha256"], owned.hashlib.sha256(sample_bytes).hexdigest())
            self.assertEqual((output / record["sample_file"]).read_bytes(), sample_bytes)
            self.assertFalse((output / "timeout.sample.raw").exists())

    def test_oversized_sample_log_retains_first_segment_and_records_truncation(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            host = output / "owned-helper"
            host.write_bytes(b"helper")
            process = mock.Mock(pid=42)
            process.poll.return_value = None
            first = b"A" * owned.SAMPLE_LOG_LIMIT
            emitted = first + b"B" * 37

            def write_large_log(_command, **kwargs):
                kwargs["stdout"].buffer.write(emitted)
                kwargs["stdout"].flush()
                return mock.Mock(returncode=0)

            with mock.patch.object(owned.subprocess, "check_output",
                                   return_value=f"{os.getuid()} {host}\n"), \
                    mock.patch.object(owned.subprocess, "run", side_effect=write_large_log):
                record = owned.sample_host(process, host, output, "late")

            retained = output / "late.sample.log"
            self.assertEqual(retained.stat().st_size, owned.SAMPLE_LOG_LIMIT)
            self.assertEqual(retained.read_bytes(), first)
            self.assertEqual(record["sample_log_original_bytes"], len(emitted))
            self.assertEqual(record["sample_log_bytes"], owned.SAMPLE_LOG_LIMIT)
            self.assertTrue(record["sample_log_truncated"])
            self.assertEqual(record["sample_log_sha256"], owned.hashlib.sha256(first).hexdigest())

    def test_watchdog_samples_then_stops_only_its_child(self):
        with tempfile.TemporaryDirectory() as temp:
            process = mock.Mock(pid=42, returncode=-15)
            process.wait.side_effect = [subprocess.TimeoutExpired("helper", 1200),
                                        subprocess.TimeoutExpired("helper", 600), -15]
            process.poll.return_value = None
            with mock.patch.object(owned, "sample_host", side_effect=lambda _process, _host, _output, label:
                                   {"phase": label}):
                timed_out, samples = owned.wait_bounded(process, Path("/tmp/owned-helper"), Path(temp))
            self.assertTrue(timed_out)
            self.assertEqual([sample["phase"] for sample in samples], ["late", "timeout"])
            process.terminate.assert_called_once_with()
            process.kill.assert_not_called()
            self.assertEqual(json.loads((Path(temp) / "samples.json").read_text()), samples)

    def test_normal_completion_keeps_the_original_result_without_sampling(self):
        with tempfile.TemporaryDirectory() as temp:
            process = mock.Mock(pid=42, returncode=0)
            process.wait.return_value = 0
            with mock.patch.object(owned, "sample_host") as sample:
                timed_out, observations = owned.wait_bounded(process, Path("/tmp/owned-helper"), Path(temp))
            self.assertFalse(timed_out)
            self.assertEqual(observations, [])
            sample.assert_not_called()
            process.terminate.assert_not_called()

    def test_normal_run_keeps_exact_status_shape_for_existing_verifiers(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            host = root / "owned-helper"
            host.write_text("#!/bin/sh\nexit 0\n")
            host.chmod(0o700)
            output = root / "result"
            with mock.patch("sys.argv", ["run-owned-package-tests.py", str(output), str(host)]):
                with self.assertRaises(SystemExit) as exit_status:
                    owned.main()
            self.assertEqual(exit_status.exception.code, 0)
            self.assertEqual(json.loads((output / "status.json").read_text()), {"returncode": 0})
            self.assertEqual(json.loads((output / "watchdog.json").read_text())["sample_phases"], [])
            self.assertFalse(json.loads((output / "watchdog.json").read_text())["timed_out"])


if __name__ == "__main__":
    unittest.main()
