#!/usr/bin/env python3
"""Own/reap the host log observer around the original actual Finder UI command."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('cancellation_preparation', Path(__file__).with_name('prepare-quicklook-cancellation-probe.py'))
PREP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREP)


def main():
    PREP.require_standard_python()
    root = Path(os.environ.get('RUNNER_TEMP', '/absent')).resolve() / 'mostlytext-qlcancel'
    PREP.require_host(root)
    if len(sys.argv) != 1:
        raise RuntimeError('This actual Finder driver accepts no command/path override')
    checkout = PREP.command(['git', 'rev-parse', 'HEAD'])
    if json.loads((root / 'receipt.json').read_text())['checkout'] != checkout:
        raise RuntimeError('Actual compiled fixture checkout changed')
    observer_command = [sys.executable, '.github/scripts/observe-quicklook-cancellation.py', str(root)]
    record = {'checkout': checkout, 'observer_command': observer_command, 'observer_forced_cleanup': False,
              'ui_started': False, 'errors': []}
    observer = None
    try:
        with (root / 'host-observer.log').open('x') as observer_log:
            observer = subprocess.Popen(observer_command, stdout=observer_log, stderr=subprocess.STDOUT, start_new_session=True)
            record['observer_pid'] = observer.pid
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if observer.poll() is not None:
                    raise RuntimeError('Host observer exited before actual UI execution')
                if (root / 'provider-observer.json').exists():
                    snapshot = json.loads((root / 'provider-observer.json').read_text())
                    if snapshot['kind'] != 'mostlytext-qlcancel-host-observer' or snapshot['checkout'] != checkout:
                        raise RuntimeError('Host observer initial snapshot differs')
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError('No actual host log-query snapshot before UI execution')
            provider = root / 'build/Build/Products/Release/QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex/Contents/MacOS/QLReplyProbeProvider'
            command = ['xcodebuild', '-project', str(root / 'fixture/QuickLookReplyProbe.xcodeproj'),
                       '-scheme', 'QuickLookReplyProbe', '-configuration', 'Release', '-destination', 'platform=macOS',
                       '-derivedDataPath', str(root / 'build'), '-resultBundlePath', str(root / 'Finder.xcresult'),
                       '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
                       '-default-test-execution-time-allowance', '120', '-maximum-test-execution-time-allowance', '120',
                       'test-without-building']
            owned_command = [sys.executable, '.github/scripts/run-owned-app-tests.py', str(root / 'owned'), str(provider), '--', *command]
            record.update(ui_started=True, command=owned_command)
            with (root / 'finder.log').open('x') as log:
                result = subprocess.run(owned_command, stdout=log, stderr=subprocess.STDOUT, timeout=660)
            record['ui_supervisor_returncode'] = result.returncode
            record['ui_completed_monotonic'] = time.monotonic()
            if result.returncode:
                raise RuntimeError('First actual Finder UI execution failed: ' + str(result.returncode))
    except BaseException as error:
        record['errors'].append(repr(error))
        raise
    finally:
        if observer is not None:
            if observer.poll() is None:
                record['observer_stop_requested_monotonic'] = time.monotonic()
                os.killpg(observer.pid, signal.SIGTERM)
                try:
                    observer.wait(timeout=6)
                except subprocess.TimeoutExpired:
                    record['observer_forced_cleanup'] = True
                    os.killpg(observer.pid, signal.SIGKILL)
                    observer.wait()
            record['observer_returncode'] = observer.returncode
        (root / 'host-ui-driver.json').write_text(json.dumps(record, indent=2) + '\n')
    observation = json.loads((root / 'observer-result.json').read_text())
    if (record['observer_forced_cleanup'] or record['observer_returncode'] != 0 or observation['errors']
            or observation['timed_out'] or not observation['stopped_after_ui'] or not observation['snapshots']):
        raise RuntimeError('Host recorder did not complete/reap normally after actual UI execution')
    print('Actual owned Finder UI and its separate host log recorder completed normally')


if __name__ == '__main__':
    main()
