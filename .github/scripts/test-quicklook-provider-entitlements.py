#!/usr/bin/env python3
"""Reject the actual test-injected provider authority that passed the old subset check."""
import gzip
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
import plistlib
import unittest

script = Path(__file__).with_name("prepare-quicklook-reply-probe.py")
spec = importlib.util.spec_from_file_location("quicklook_preparation", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = script.resolve().parents[2]


class ProviderEntitlementsTests(unittest.TestCase):
    def test_actual_retained_native_permissions_are_rejected(self):
        path = root / "planning/downstream/evidence/quicklook-hosted-feasibility-2026-11-07/b000-receipt.json.gz"
        actual = json.loads(gzip.decompress(path.read_bytes()))["built"]["entitlements"]
        self.assertEqual(actual["com.apple.security.temporary-exception.files.absolute-path.read-only"], ["/"])
        with self.assertRaises(AssertionError):
            module.validate_provider_entitlements(actual)

    def test_exact_declared_provider_permissions_are_admitted(self):
        actual = plistlib.loads((root / ".github/quicklook-reply-probe/Provider.entitlements").read_bytes())
        module.validate_provider_entitlements(actual)

    def test_optimized_preparation_refuses_before_first_mutation(self):
        with tempfile.TemporaryDirectory(prefix="mostlytext-ql-guard-") as temporary:
            target = Path(temporary) / "must-not-create"
            event = Path(temporary) / "event.json"
            event.write_text("{}")
            common = "import importlib.util,inspect,sys;from pathlib import Path\n"
            common += "spec=importlib.util.spec_from_file_location('prep'," + repr(str(script)) + ");module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)\n"
            common += "sys.argv=['probe'," + repr(str(target)) + "]\n"
            common += "class MutationAttempt(Exception): pass\n"
            common += "def trap(*args,**kwargs): raise MutationAttempt('first mutation intercepted')\n"
            common += "module.Path.mkdir=trap\n"
            before = common + "source=inspect.getsource(module.main).replace('    require_standard_python()\\n','');namespace=dict(module.__dict__);exec(compile(source,'<assertion-only-main-before>','exec'),namespace)\n"
            before += "try: namespace['main']()\nexcept MutationAttempt: print('OLD_GUARD_REACHED_MUTATION')\n"
            environment = dict(os.environ, GITHUB_ACTIONS="false", GITHUB_EVENT_PATH=str(event), GITHUB_EVENT_NAME="workflow_dispatch")
            result = subprocess.run([sys.executable, "-O", "-c", before], env=environment, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("OLD_GUARD_REACHED_MUTATION", result.stdout)
            result = subprocess.run([sys.executable, "-O", "-c", common + "module.main()\n"], env=environment, capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Optimized Python cannot enforce", result.stderr)
            self.assertNotIn("first mutation intercepted", result.stderr)
            self.assertFalse(target.exists())

    def test_foreign_pr_head_is_refused(self):
        with self.assertRaises(RuntimeError):
            module.validate_trusted_event({"pull_request": {"head": {"repo": {"full_name": "foreign/fork"}}}}, "pull_request")
        module.validate_trusted_event({"pull_request": {"head": {"repo": {"full_name": "Joncallim/mostlytext"}}}}, "pull_request")
        module.validate_trusted_event({}, "workflow_dispatch")


if __name__ == "__main__":
    unittest.main()
