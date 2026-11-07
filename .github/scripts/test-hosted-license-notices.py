#!/usr/bin/env python3
"""Check held execution and host-before-receipt order without opening a receipt."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("run-hosted-public-focus.py")


def read_order(source):
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "LICENSE_NOTICES_QUALIFIED_MAIN" for t in node.targets):
            node.value = ast.Constant("0" * 40)
    scope = {"__file__": str(SCRIPT), "__name__": "read_order_control"}
    exec(compile(ast.fix_missing_locations(tree), str(SCRIPT), "exec"), scope)
    reads = []
    commands = []

    def intercept(path, *_args, **_kwargs):
        reads.append(str(path))
        raise RuntimeError("Intercepted receipt read; no file opened")

    def ancestry(arguments, **_kwargs):
        if arguments != ["git", "merge-base", "--is-ancestor", "0" * 40, "HEAD"]:
            raise RuntimeError("Unexpected command refused without execution")
        commands.append(arguments)
        return subprocess.CompletedProcess(arguments, 0)

    with mock.patch.dict(os.environ, {}, clear=True), \
         mock.patch.object(sys, "argv", [str(SCRIPT), "/nonexistent-held-fixture", "--license-notices-probe"]), \
         mock.patch.object(subprocess, "run", ancestry), \
         mock.patch.object(Path, "read_text", intercept):
        try:
            scope["main"]()
        except (RuntimeError, AssertionError) as error:
            return reads, commands, error
    raise AssertionError("Untrusted host unexpectedly admitted")


class LicenseAdmissionTests(unittest.TestCase):
    def test_actual_host_guard_precedes_ancestry_and_receipt_read(self):
        source = SCRIPT.read_text()
        self.assertEqual(source.count("    preparation.check_host(root)\n"), 1)
        reads, commands, error = read_order(source.replace("    preparation.check_host(root)\n", ""))
        self.assertEqual(len(reads), 1)
        self.assertEqual(len(commands), 1)
        self.assertIn("Intercepted receipt read", str(error))
        reads, commands, error = read_order(source)
        self.assertEqual(reads, [])
        self.assertEqual(commands, [])
        self.assertNotIn("Intercepted receipt read", str(error))

    def test_normal_held_selection_refuses_before_host_access(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "/nonexistent-held-fixture", "--license-notices-probe"],
                                capture_output=True, env={"PATH": os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Licence execution is held", result.stderr)

    def test_optimized_interpreter_refuses_before_host_access(self):
        result = subprocess.run([sys.executable, "-B", "-O", str(SCRIPT), "/nonexistent-held-fixture", "--license-notices-probe"],
                                capture_output=True, env={"PATH": os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Optimized Python is refused", result.stderr)


if __name__ == "__main__":
    if sys.flags.optimize:
        raise RuntimeError("Run counterexamples normally; optimized refusal is tested in a child")
    unittest.main()
