#!/usr/bin/env python3
"""Reject the actual test-injected provider authority that passed the old subset check."""
import gzip
import importlib.util
import json
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


if __name__ == "__main__":
    unittest.main()
