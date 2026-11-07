#!/usr/bin/env python3
"""Exercise only the literal Foundation/Darwin admission helper, never app code."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'hosted-migration/Fixture/SeedAdmission.swift'
CONTROL = '''import Foundation
@main struct Control {
 static func main() {
  do { _ = try MigrationSeedAdmission.requirePositive(); print("UNEXPECTED_ADMISSION") }
  catch MigrationSeedAdmission.Refusal.held { print("held") }
  catch MigrationSeedAdmission.Refusal.host { print("host") }
  catch { print("receipt-read-counterexample: \\(String(reflecting: error))") }
 }
}
'''


class SeedAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if Path('/Users/runner').exists():
            raise RuntimeError('These negative controls require an untrusted non-runner host; no profile is read')
        cls.temporary = tempfile.TemporaryDirectory(prefix='mostlytext-seed-admission-')
        cls.root = Path(cls.temporary.name)
        cls.source = SOURCE.read_text()
        import re
        cls.anchor = re.search(r'qualifiedMain = "([^"]+)"', cls.source).group(1)
        cls.future_anchor = re.search(r'futureQualifiedMain = "([^"]+)"', cls.source).group(1)
        (cls.root / 'Control.swift').write_text(CONTROL)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def observe(self, source, environment=None, future=False):
        control = CONTROL.replace('requirePositive()', 'requireFutureHost()') if future else CONTROL
        (self.root / 'Control.swift').write_text(control)
        (self.root / 'Admission.swift').write_text(source)
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6',
                        '-strict-concurrency=complete', '-O', str(self.root / 'Admission.swift'),
                        str(self.root / 'Control.swift'), '-o', str(self.root / 'control')], check=True,
                       capture_output=True, timeout=60)
        result = subprocess.run([str(self.root / 'control')], env=environment or {'PATH': os.defpath},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_actual_held_and_activated_anchors_refuse_before_any_receipt_access(self):
        self.assertEqual(self.observe(self.source), 'host')
        held = self.source.replace(self.anchor, 'PENDING_CONTROL_ANCHOR')
        self.assertEqual(self.observe(held), 'held')

    def test_admitted_anchor_still_refuses_real_untrusted_account(self):
        source = self.source.replace(self.anchor, '0' * 40)
        # Claimed CI variables cannot replace the actual account/home identity.
        environment = {'PATH': os.defpath, 'GITHUB_ACTIONS': 'true', 'RUNNER_OS': 'macOS',
                       'GITHUB_REPOSITORY': 'Joncallim/mostlytext', 'RUNNER_TEMP': '/Users/runner/work/_temp'}
        self.assertEqual(self.observe(source, environment), 'host')

    def test_removed_guard_reaches_missing_private_receipt_before_any_profile(self):
        guard = '        try requireHost()\n        let receipt ='
        self.assertEqual(self.source.count(guard), 1)
        removed = self.source.replace(guard, '        let receipt =')
        self.assertTrue(self.observe(removed).startswith('receipt-read-counterexample:'))
        self.assertEqual(self.observe(self.source), 'host')

    def test_future_held_anchor_precedes_actual_host_or_any_receipt(self):
        import re
        expected = 'host' if re.fullmatch('[0-9a-f]{40}', self.future_anchor) else 'held'
        self.assertEqual(self.observe(self.source, future=True), expected)
        held = self.source.replace(self.future_anchor, 'PENDING_CONTROL_ANCHOR')
        self.assertEqual(self.observe(held, future=True), 'held')
        source = self.source.replace(self.future_anchor, '0' * 40)
        self.assertEqual(self.observe(source, future=True), 'host')


if __name__ == '__main__':
    print(json.dumps({'actual_helper_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      'scope': 'Literal Foundation/Darwin helper only. No app/package/GUI or profile/defaults operation.'}), flush=True)
    unittest.main()
