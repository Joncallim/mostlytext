#!/usr/bin/env python3
"""Observe a separate staged case without retesting or replacing the original failed selection."""
import json
import os
from pathlib import Path
import subprocess
import sys
from preview_compiled_inputs import capture, check_host, require_owned_phase, verify


def main():
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python cannot enforce Preview diagnostic admission')
    root = Path(os.environ['RUNNER_TEMP']).resolve() / 'preview-grant-probe'
    check_host(root)
    receipt = json.loads((root / 'receipt.json').read_bytes())
    if receipt['diagnostic_only'] is not True or receipt['qualification_candidate'] is not False:
        raise RuntimeError('This phase is diagnostic only and cannot qualify a candidate')
    subprocess.run([sys.executable, '.github/scripts/verify-preview-grant-probe.py', str(root), 'Debug',
                    '--pair', 'revision', '--verify'], check=True, timeout=30)
    original = json.loads((root / 'compiled-initial.json').read_bytes())
    if original['configuration'] != 'Debug' or original['phase'] != 'initial':
        raise RuntimeError('The original Debug compiled phase is required')
    verify(root, original)
    first = json.loads((root / 'diagnostics/identity.json').read_bytes())
    require_owned_phase(first, original, receipt['checkout'])
    folder = root / 'delayed-grant-diagnosis'
    folder.mkdir(mode=0o700)
    binding = capture(folder, Path(os.environ['RUNNER_TEMP']) / 'preview-grant-app/Build/Products',
                      'Debug', Path.cwd() / 'MacDown2/MacDown2.xcodeproj', 'initial')
    if binding['inputs'] != original['inputs']:
        raise RuntimeError('A leftover mutated or rebuilt product cannot run the separate staged case')
    command = first['command']
    if (command[0] != 'xcodebuild' or command[-1] != 'test-without-building'
            or command[command.index('-configuration') + 1] != 'Debug'
            or command.count('-resultBundlePath') != 1 or command.count('-destination') != 1
            or command[command.index('-destination') + 1] != 'platform=macOS,arch=arm64'):
        raise RuntimeError('Original diagnostic command differs')
    selected = []
    for value in command:
        if value.startswith('-only-testing:') or value.startswith('-skip-testing:'):
            continue
        selected.append(value)
    selected[selected.index('-resultBundlePath') + 1] = str(folder / 'actual-staged.xcresult')
    selected.insert(-1, '-only-testing:MacDown2Tests/PreviewDelayedGrantDiagnosisTests')
    with (folder / 'probe.log').open('x') as log:
        result = subprocess.run([sys.executable, '.github/scripts/run-owned-app-tests.py',
                                 str(folder / 'diagnostics'), first['app'], '--', *selected],
                                stdout=log, stderr=subprocess.STDOUT, timeout=660)
    identity = json.loads((folder / 'diagnostics/identity.json').read_bytes())
    owned = json.loads((folder / 'diagnostics/status.json').read_bytes())
    require_owned_phase(identity, binding, receipt['checkout'])
    verify(folder, binding)
    raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                   '--path', str(folder / 'actual-staged.xcresult')])
    (folder / 'actual-staged-summary.json').write_bytes(raw)
    summary = json.loads(raw)
    record = {'checkout': receipt['checkout'], 'diagnostic_only': True, 'qualification_candidate': False,
              'original_initial_owned': json.loads((root / 'diagnostics/status.json').read_bytes()),
              'selected': 'MacDown2Tests/PreviewDelayedGrantDiagnosisTests',
              'actual_owned': owned, 'actual_summary': summary, 'command_returncode': result.returncode,
              'original_compiled_inputs_unchanged': True,
              'scope': 'Separate already-bound and controlled baseline-during-grant cases. Neither their pass nor a diagnostic original pass waives the historical production failure.'}
    (folder / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    expected = {'totalTestCount': 2, 'passedTests': 2, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
    if (result.returncode != 0 or owned['returncode'] != 0 or owned['timed_out'] or owned['cancelled']
            or owned['app_cleanup_requested'] or any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items())):
        raise RuntimeError('The separate first staged diagnostic did not pass; evidence retained')
    subprocess.run([sys.executable, '.github/scripts/verify-preview-grant-probe.py', str(root), 'Debug',
                    '--pair', 'revision', '--verify'], check=True, timeout=30)
    print('Both separate staged current-document denial/grant cases passed; original failed qualification is unchanged')


if __name__ == '__main__':
    main()
