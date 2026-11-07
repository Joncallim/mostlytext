#!/usr/bin/env python3
"""Intercept the first inventory command; never run it or touch native state."""
import os
from pathlib import Path
import platform
import subprocess
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("verify-preview-grant-probe.py")


def inventory_order(source):
    operations = []

    def intercept(*args, **_kwargs):
        operations.append(args)
        raise RuntimeError("Intercepted source inventory; no command executed")

    environment = {"RUNNER_TEMP": "/tmp/preview-diagnostic-control", "MOSTLYTEXT_PREVIEW_RESOURCE_TRACE": "1",
                   "TEST_RUNNER_MOSTLYTEXT_PREVIEW_RESOURCE_TRACE": "1"}
    with mock.patch.dict(os.environ, environment, clear=True), \
         mock.patch.object(sys, "argv", [str(SCRIPT), "/tmp/preview-diagnostic-control/preview-grant-probe",
                                         "Debug", "--pair", "revision"]), \
         mock.patch.object(platform, "machine", return_value="arm64"), \
         mock.patch.object(subprocess, "check_output", intercept):
        try:
            exec(compile(source, str(SCRIPT), "exec"), {"__file__": str(SCRIPT), "__name__": "inventory_order_control"})
        except (AssertionError, RuntimeError) as error:
            return operations, error
    raise AssertionError("Untrusted host unexpectedly admitted")


class DiagnosticHostTests(unittest.TestCase):
    def test_actual_host_guard_precedes_inventory_and_removed_guard_reaches_it(self):
        source = SCRIPT.read_text()
        call = "check_diagnostic_host(args.output.resolve())\n"
        self.assertEqual(source.count(call), 1)
        operations, error = inventory_order(source.replace(call, ""))
        self.assertEqual(len(operations), 1)
        self.assertIn("Intercepted source inventory", str(error))
        operations, error = inventory_order(source)
        self.assertEqual(operations, [])
        self.assertNotIn("Intercepted source inventory", str(error))

    def test_optimized_python_refuses_before_argument_or_environment_access(self):
        result = subprocess.run([sys.executable, "-B", "-O", str(SCRIPT)], capture_output=True,
                                env={"PATH": os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Optimized Python is refused", result.stderr)
        self.assertNotIn(b"RUNNER_TEMP", result.stderr)


if __name__ == "__main__":
    if sys.flags.optimize:
        raise RuntimeError("Run the inventory-order counterexample normally")
    unittest.main()
