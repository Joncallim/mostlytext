#!/usr/bin/env python3
"""Prove untrusted hosts cannot read a journey receipt; never open that receipt."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("run-hosted-critical-journey.py")


def read_order(source):
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "QUALIFIED_MAIN" for t in node.targets):
            node.value = ast.Constant("0" * 40)
    scope = {"__file__": str(SCRIPT), "__name__": "read_order_control"}
    exec(compile(ast.fix_missing_locations(tree), str(SCRIPT), "exec"), scope)
    reads = []

    def intercept(path, *_args, **_kwargs):
        reads.append(str(path))
        raise RuntimeError("Intercepted receipt read; no file opened")

    with mock.patch.dict(os.environ, {"RUNNER_TEMP": "/tmp/mostlytext-read-order-control"}, clear=True), \
         mock.patch.object(sys, "argv", [str(SCRIPT), "execute", "--journey", "native-tabs-dirty-close"]), \
         mock.patch.object(Path, "read_text", intercept):
        try:
            scope["main"]()
        except (RuntimeError, AssertionError) as error:
            return reads, error
    raise AssertionError("Untrusted host unexpectedly admitted")


class CriticalJourneyAdmissionTests(unittest.TestCase):
    def test_actual_guard_precedes_receipt_read_and_removed_guard_reaches_it(self):
        source = SCRIPT.read_text()
        self.assertEqual(source.count("    guard.check_host(root)\n"), 1)
        before_reads, before_error = read_order(source.replace("    guard.check_host(root)\n", ""))
        self.assertEqual(len(before_reads), 1)
        self.assertIn("Intercepted receipt read", str(before_error))
        current_reads, current_error = read_order(source)
        self.assertEqual(current_reads, [])
        self.assertNotIn("Intercepted receipt read", str(current_error))

    def test_optimized_interpreter_refuses_before_environment_access(self):
        result = subprocess.run([sys.executable, "-B", "-O", str(SCRIPT), "prepare", "--journey", "native-tabs-dirty-close"],
                                capture_output=True, env={"PATH": os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Optimized Python is refused", result.stderr)
        self.assertNotIn(b"RUNNER_TEMP", result.stderr)


if __name__ == "__main__":
    if sys.flags.optimize:
        raise RuntimeError("Run the read-order counterexample normally; optimized refusal is tested in a child")
    unittest.main()
