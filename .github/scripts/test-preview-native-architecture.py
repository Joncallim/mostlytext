#!/usr/bin/env python3
"""Refuse a native Preview receipt that silently expands or changes architecture."""
import ast
from pathlib import Path
import unittest

source = Path(__file__).with_name('verify-preview-grant-probe.py')
module = ast.parse(source.read_text())
function = next(node for node in module.body if isinstance(node, ast.FunctionDef)
                and node.name == 'verify_native_architecture')
namespace = {}
exec(compile(ast.Module(body=[function], type_ignores=[]), str(source), 'exec'), namespace)
verify = namespace['verify_native_architecture']


class NativeArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.receipt = {'execution_architecture': 'arm64', 'only_active_arch': True}
        self.identity = {'command': ['xcodebuild', '-destination', 'platform=macOS,arch=arm64',
                                     'ONLY_ACTIVE_ARCH=YES', 'test-without-building']}

    def test_exact_native_worker_build_and_execution_accepts(self):
        verify(self.receipt, self.identity, ['arm64'])

    def test_missing_wrong_or_universal_architecture_refuses(self):
        for receipt in [{}, {'execution_architecture': 'x86_64', 'only_active_arch': True},
                        {'execution_architecture': 'arm64', 'only_active_arch': False}]:
            with self.subTest(receipt=receipt), self.assertRaises(SystemExit):
                verify(receipt, self.identity, ['arm64'])
        for architectures in [[], ['x86_64'], ['arm64', 'x86_64']]:
            with self.subTest(architectures=architectures), self.assertRaises(SystemExit):
                verify(self.receipt, self.identity, architectures)

    def test_unowned_wrong_destination_or_missing_policy_refuses(self):
        for command in [[], ['helper'], ['xcodebuild', '-destination', 'platform=macOS,arch=arm64'],
                        ['xcodebuild', '-destination', 'platform=macOS', 'ONLY_ACTIVE_ARCH=YES'],
                        ['xcodebuild', 'ONLY_ACTIVE_ARCH=YES', 'test-without-building', '-destination'],
                        self.identity['command'] + ['ONLY_ACTIVE_ARCH=NO'],
                        self.identity['command'] + ['-destination', 'platform=macOS,arch=x86_64']]:
            with self.subTest(command=command), self.assertRaises(SystemExit):
                verify(self.receipt, {'command': command}, ['arm64'])


if __name__ == '__main__':
    unittest.main()
