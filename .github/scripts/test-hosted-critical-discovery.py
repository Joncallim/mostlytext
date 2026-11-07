#!/usr/bin/env python3
"""Check discovery admission with intercepted receipt reads, never native work."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("run-hosted-critical-discovery.py")


def read_order(source, anchor="0" * 40):
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "QUALIFIED_MAIN" for t in node.targets):
            node.value = ast.Constant(anchor)
    scope = {"__file__": str(SCRIPT), "__name__": "read_order_control"}
    exec(compile(ast.fix_missing_locations(tree), str(SCRIPT), "exec"), scope)
    reads = []

    def intercept(path, *_args, **_kwargs):
        reads.append(str(path))
        raise RuntimeError("Intercepted receipt read; no file opened")

    with mock.patch.dict(os.environ, {"RUNNER_TEMP": "/tmp/discovery-read-order-control"}, clear=True), \
         mock.patch.object(sys, "argv", [str(SCRIPT), "execute"]), \
         mock.patch.object(Path, "read_text", intercept):
        try:
            scope["main"]()
        except (RuntimeError, AssertionError) as error:
            return reads, error
    raise AssertionError("Untrusted host unexpectedly admitted")


class CriticalDiscoveryAdmissionTests(unittest.TestCase):
    def test_actual_host_guard_precedes_receipt_read(self):
        source = SCRIPT.read_text()
        self.assertEqual(source.count("    guard.check_host(root)\n"), 1)
        reads, error = read_order(source.replace("    guard.check_host(root)\n", ""))
        self.assertEqual(len(reads), 1)
        self.assertIn("Intercepted receipt read", str(error))
        reads, error = read_order(source)
        self.assertEqual(reads, [])
        self.assertNotIn("Intercepted receipt read", str(error))

    def test_unresolved_anchor_refuses_before_host_and_receipt_access(self):
        reads, error = read_order(SCRIPT.read_text(), "PENDING_CONTROL_ANCHOR")
        self.assertEqual(reads, [])
        self.assertIn("Critical discovery is held", str(error))

    def test_optimized_python_refuses_before_environment_access(self):
        result = subprocess.run([sys.executable, "-B", "-O", str(SCRIPT), "prepare"],
                                capture_output=True, env={"PATH": os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Optimized Python is refused", result.stderr)
        self.assertNotIn(b"RUNNER_TEMP", result.stderr)


if __name__ == "__main__":
    if sys.flags.optimize:
        raise RuntimeError("Run read-order controls normally; optimized refusal is tested in a child")
    unittest.main()
