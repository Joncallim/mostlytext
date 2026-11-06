#!/usr/bin/env python3
"""Exercise the real loopback listener with pure HTTP controls, without launching any native product."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.request

spec = importlib.util.spec_from_file_location('preview_tripwire', Path(__file__).with_name('run-preview-grant-probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class TripwireControls(unittest.TestCase):
    def exercise(self, paths, *, status=0, configuration='Debug'):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'observed.json'
            observed_environment = {}

            def http_only_command(command, *, env, timeout):
                self.assertEqual(command, ['http-control-only'])
                self.assertEqual(timeout, 660)
                observed_environment.update(env)
                for path in paths:
                    with urllib.request.urlopen(env['MOSTLYTEXT_PREVIEW_TRIPWIRE'] + path, timeout=2) as response:
                        self.assertEqual(response.status, 200)
                        response.read()
                return subprocess.CompletedProcess(command, status)

            with patch.object(sys, 'argv', ['probe', str(output), configuration, '--', 'http-control-only']), \
                 patch.dict(probe.os.environ, {'CI': 'true'}), \
                 patch.object(probe.subprocess, 'run', side_effect=http_only_command):
                try:
                    probe.main()
                    result = 0
                except SystemExit as error:
                    result = error.code
            return result, json.loads(output.read_text()), observed_environment

    def test_both_independent_positive_controls_are_required(self):
        status, observed, environment = self.exercise(['/control', '/control-webkit', '/status'])
        self.assertEqual(status, 0)
        self.assertEqual(observed['paths'], ['/control', '/control-webkit'])
        self.assertEqual(observed['denied_requests'], [])
        self.assertEqual(environment['TEST_RUNNER_MOSTLYTEXT_PREVIEW_TRIPWIRE'], environment['MOSTLYTEXT_PREVIEW_TRIPWIRE'])

    def test_dead_webkit_control_cannot_qualify_a_listener(self):
        status, _, _ = self.exercise(['/control'])
        self.assertNotEqual(status, 0)

    def test_a_real_hostile_request_prevents_acceptance(self):
        status, observed, _ = self.exercise(['/control', '/control-webkit', '/denied/image.png'])
        self.assertNotEqual(status, 0)
        self.assertEqual(observed['denied_requests'], ['/denied/image.png'])

    def test_native_command_failure_is_never_overridden_by_http_controls(self):
        status, _, _ = self.exercise(['/control', '/control-webkit'], status=34)
        self.assertEqual(status, 34)

    def test_optimized_measurement_is_explicitly_forwarded(self):
        status, _, environment = self.exercise(['/control', '/control-webkit'], configuration='Release')
        self.assertEqual(status, 0)
        self.assertEqual(environment['TEST_RUNNER_MOSTLYTEXT_PREVIEW_RELEASE_PROBE'], '1')


if __name__ == '__main__':
    unittest.main()
