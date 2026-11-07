"""Real isolated Darwin kernel controls, without launching any application."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from native_cli_endpoint_probe import probe_endpoint


class EndpointProbeTests(unittest.TestCase):
    observations = []

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mostlytext-peer-control-")
        self.root = Path(self.temporary.name)
        self.path = self.root / "s"
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(self.path))
        self.path.chmod(0o600)
        self.listener.listen(8)

    def tearDown(self):
        self.listener.close()
        self.temporary.cleanup()

    def observe(self, name, expected_pid=None):
        value = probe_endpoint(self.path, os.getpid() if expected_pid is None else expected_pid)
        self.observations.append({"case": name, "observed": value})
        return value

    def test_live_current_process_is_accepted(self):
        value = self.observe("live-current-process")
        self.assertTrue(value["ready"])
        self.assertEqual(value["peer_pid"], os.getpid())
        self.assertEqual(value["peer_uid"], os.geteuid())

    def test_live_wrong_process_is_refused(self):
        value = self.observe("live-wrong-process", os.getpid() + 1)
        self.assertFalse(value["ready"])
        self.assertEqual(value["peer_pid"], os.getpid())

    def test_closed_socket_existence_does_not_establish_readiness(self):
        self.listener.close()
        self.assertTrue(self.path.exists(), "The original path-existence oracle must accept this stale node")
        self.assertFalse(self.observe("closed-existing-socket")["ready"])
        self.assertTrue(self.path.exists(), "The observer must not remove the stale node")

    def test_wrong_permissions_are_preserved_and_refused(self):
        self.path.chmod(0o644)
        self.assertFalse(self.observe("wrong-permissions")["ready"])
        self.assertEqual(self.path.stat().st_mode & 0o7777, 0o644)

    def test_symlink_is_preserved_and_never_connected(self):
        target = self.root / "target"
        self.path.rename(target)
        self.path.symlink_to(target)
        self.assertFalse(self.observe("symlink")["ready"])
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(os.readlink(self.path), str(target))
        self.listener.settimeout(0.01)
        with self.assertRaises(socket.timeout):
            self.listener.accept()

    def test_regular_file_is_preserved_and_refused(self):
        self.listener.close()
        self.path.unlink()
        self.path.write_bytes(b"owned control sentinel")
        self.path.chmod(0o600)
        self.assertFalse(self.observe("regular-file")["ready"])
        self.assertEqual(self.path.read_bytes(), b"owned control sentinel")


if __name__ == "__main__":
    assert sys.platform == "darwin", "These are actual Darwin peer controls, not skipped Linux passes"
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EndpointProbeTests))
    record = {"tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
              "passed": result.wasSuccessful(), "observations": EndpointProbeTests.observations,
              "module_sha256": hashlib.sha256(Path(__file__).with_name("native_cli_endpoint_probe.py").read_bytes()).hexdigest(),
              "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "scope": "Generated private Darwin Unix sockets only; no application launch, document request or owner-native acceptance"}
    if args.report:
        with args.report.open("x") as out:
            out.write(json.dumps(record, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
