#!/usr/bin/env python3
"""Prepare a private normal Release stdin/Save As journey after actual integration."""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
from hosted_cli_stdin_contract import capture, read_regular, sha, verify

QUALIFIED_PREVIEW_MAIN = 'PENDING_ACTUAL_QUALIFIED_PREVIEW_MAIN'
ROOT_SOURCES = ['.github/hosted-cli-stdin-save', '.github/scripts/prepare-hosted-cli-stdin-save.py',
                '.github/scripts/run-hosted-cli-stdin-save.py', '.github/scripts/hosted_cli_stdin_contract.py',
                '.github/scripts/test-hosted-cli-stdin-save.py', '.github/workflows/hosted-cli-stdin-save.yml']


def preparation_module():
    spec = importlib.util.spec_from_file_location('public_focus_preparation', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def admit(root):
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python cannot enforce the hosted stdin contract')
    preparation_module().check_host(root)
    if not re.fullmatch('[0-9a-f]{40}', QUALIFIED_PREVIEW_MAIN):
        raise RuntimeError('Execution held until actual qualified Preview main integration')
    subprocess.run(['git', 'merge-base', '--is-ancestor', QUALIFIED_PREVIEW_MAIN, 'HEAD'], check=True, timeout=15)


def compiled_paths(root, receipt):
    products = root / 'control/Build/Products'
    tests = list(products.rglob('HostedFocusDriverTests.xctest/Contents/MacOS/HostedFocusDriverTests'))
    plans = list(products.glob('*.xctestrun'))
    if len(tests) != 1 or len(plans) != 1:
        raise RuntimeError('Expected exactly one actual independent driver and run plan')
    plan = plistlib.loads(read_regular(plans[0]))
    target = plan.get('HostedFocusDriverTests', {})
    expected = {'TestHostPath': '__TESTROOT__/Release/HostedFocusDriverTests-Runner.app',
                'TestBundlePath': '__TESTHOST__/Contents/PlugIns/HostedFocusDriverTests.xctest',
                'UITargetAppPath': '__TESTROOT__/Release/HostedFocusControl.app', 'IsUITestBundle': True}
    if any(target.get(k) != v for k, v in expected.items()):
        raise RuntimeError('Actual UI run plan does not target the independent control')
    expected_driver = products / 'Release/HostedFocusDriverTests-Runner.app/Contents/PlugIns/HostedFocusDriverTests.xctest/Contents/MacOS/HostedFocusDriverTests'
    if tests[0] != expected_driver:
        raise RuntimeError('Captured driver is outside the actual UI runner')
    return {'app': Path(receipt['built']['executable']), 'helper': Path(receipt['built']['helper']),
            'app_info': Path(receipt['built']['app']) / 'Contents/Info.plist',
            'controller': root / 'normal-app-host', 'host_facts': root / 'host-facts',
            'absence': root / 'product-absence',
            'control': products / 'Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl',
            'driver': tests[0], 'runplan': plans[0],
            'project': root / 'fixture/HostedPublicFocus.xcodeproj/project.pbxproj'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--phase', choices=['admit', 'prepare', 'bind-built', 'bind-driver', 'verify'], required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    admit(root)
    if args.phase == 'admit':
        return
    base = Path(__file__).with_name('prepare-hosted-public-focus.py')
    if args.phase == 'prepare':
        subprocess.run([sys.executable, str(base), str(root)], check=True, timeout=60)
        path = root / 'receipt.json'
        receipt = json.loads(read_regular(path))
        tracked = subprocess.check_output(['git', 'ls-files', '--', *ROOT_SOURCES], text=True).splitlines()
        if not tracked or '.github/scripts/run-hosted-cli-stdin-save.py' not in tracked:
            raise RuntimeError('Commit all reviewed stdin inputs before preparing the native fixture')
        payload = '# Public stdin — 🙂\n\nCafe\u0301; αβ; line two.\n'.encode('utf-8')
        oracle = root / 'stdin-oracle.md'
        oracle.write_bytes(payload)
        saved = root / 'documents/cli-saved-stdin.md'
        if saved.exists():
            raise RuntimeError('Refuse an existing output document')
        values = {'oracle': str(oracle), 'saved': str(saved), 'folder': str(saved.parent)}
        generated = '// Generated only for the disposable hosted runner.\nenum CLIStdinInputs {\n'
        generated += ''.join('    static let ' + key + ' = ' + json.dumps(value) + '\n' for key, value in values.items()) + '}\n'
        (root / 'fixture/Driver/CLIStdinInputs.swift').write_text(generated)
        shutil.copyfile('.github/hosted-cli-stdin-save/CLIStdinTests.swift', root / 'fixture/Driver/CLIStdinTests.swift')
        receipt['cli_stdin'] = {'qualified_preview_main': QUALIFIED_PREVIEW_MAIN,
                                'source_sha256': {p: sha(p) for p in tracked},
                                'oracle': str(oracle), 'oracle_sha256': sha(oracle),
                                'saved': str(saved), 'saved_must_be_absent': True,
                                'scope': 'Hosted untrusted cold refusal, ordinary warm stdin/readback/save, not trusted signed cold success'}
        path.write_text(json.dumps(receipt, indent=2) + '\n')
        return
    path = root / 'receipt.json'
    receipt = json.loads(read_regular(path))
    extra = receipt['cli_stdin']
    tracked = subprocess.check_output(['git', 'ls-files', '--', *ROOT_SOURCES], text=True).splitlines()
    if (extra['qualified_preview_main'] != QUALIFIED_PREVIEW_MAIN
            or extra['source_sha256'] != {p: sha(p) for p in tracked}
            or sha(extra['oracle']) != extra['oracle_sha256']):
        raise RuntimeError('Canonical stdin inputs or original oracle changed')
    if (read_regular(root / 'fixture/Driver/CLIStdinTests.swift')
            != read_regular('.github/hosted-cli-stdin-save/CLIStdinTests.swift')):
        raise RuntimeError('Generated stdin driver differs from canonical source')
    if args.phase == 'bind-built':
        subprocess.run([sys.executable, str(base), str(root), '--bind-built'], check=True, timeout=60)
        return
    subprocess.run([sys.executable, str(base), str(root), '--verify'], check=True, timeout=60)
    receipt = json.loads(read_regular(path))
    paths = compiled_paths(root, receipt)
    if args.phase == 'bind-driver':
        capture(root, paths)
    else:
        verify(root, paths)
    print('Exact canonical stdin inputs, original oracle and compiled bytes verified')


if __name__ == '__main__':
    main()
