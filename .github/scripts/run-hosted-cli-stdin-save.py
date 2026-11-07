#!/usr/bin/env python3
"""One ordinary public stdin/save journey, with original first outcomes retained."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from hosted_cli_stdin_contract import read_regular, require_ui, sha
from native_cli_endpoint_probe import probe_endpoint


def main():
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before stdin preparation')
    if len(sys.argv) != 2:
        raise RuntimeError('Pass only the fixed owned hosted root')
    spec = importlib.util.spec_from_file_location('stdin_preparation', Path(__file__).with_name('prepare-hosted-cli-stdin-save.py'))
    preparation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preparation)
    root = Path(sys.argv[1]).resolve()
    preparation.admit(root)
    path = root / 'receipt.json'
    receipt = json.loads(read_regular(path))
    receipt['cli_stdin_results'] = {'criteria': {}, 'errors': [], 'commands': [], 'applications': [], 'ui_results': {}}
    record = receipt['cli_stdin_results']
    current = None

    def persist():
        path.write_text(json.dumps(receipt, indent=2) + '\n')

    def command(label, arguments, data=None, timeout=20):
        started = time.monotonic()
        try:
            value = subprocess.run([str(a) for a in arguments], input=data, capture_output=True, timeout=timeout)
            code, out, err, expired = value.returncode, value.stdout, value.stderr, False
        except subprocess.TimeoutExpired as error:
            code, out, err, expired = 124, error.stdout or b'', error.stderr or b'', True
        row = {'label': label, 'command': [str(a) for a in arguments], 'returncode': code,
               'stdout': out.decode('utf-8', errors='replace')[:131072],
               'stderr': err.decode('utf-8', errors='replace')[:131072],
               'timed_out': expired, 'elapsed_seconds': time.monotonic() - started}
        record['commands'].append(row)
        persist()
        return row

    def checked(label, arguments, data=None, timeout=20):
        row = command(label, arguments, data, timeout)
        if row['returncode'] != 0 or row['timed_out']:
            raise RuntimeError('Actual operation failed: ' + label)
        return row

    def action(operation, identity=None):
        args = [root / 'normal-app-host', operation, receipt['built']['app']]
        if identity is not None:
            args += [str(identity['pid']), str(identity['birth'])]
        value = json.loads(checked('app-' + operation, args)['stdout'])
        record['applications'].append(value)
        persist()
        return value

    def ui_phase(label, selected):
        control = root / 'control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl'
        args = [sys.executable, '.github/scripts/run-owned-app-tests.py', str(root / (label + '-owned')), str(control), '--',
                'xcodebuild', '-project', str(root / 'fixture/HostedPublicFocus.xcodeproj'), '-scheme', 'HostedPublicFocus',
                '-configuration', 'Release', '-destination', 'platform=macOS', '-derivedDataPath', str(root / 'control'),
                '-resultBundlePath', str(root / (label + '.xcresult')), '-parallel-testing-enabled', 'NO',
                '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '120',
                '-maximum-test-execution-time-allowance', '120', '-only-testing:' + selected, 'test-without-building']
        with (root / (label + '.log')).open('x') as output:
            actual = subprocess.run(args, stdout=output, stderr=subprocess.STDOUT)
        summary = json.loads(checked(label + '-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                                       '--path', root / (label + '.xcresult')])['stdout'])
        owned = json.loads(read_regular(root / (label + '-owned/status.json')))
        record['ui_results'][label] = {'selected': selected, 'returncode': actual.returncode, 'summary': summary, 'owned': owned}
        persist()
        require_ui(summary, owned, actual.returncode)
        target, cls, method = selected.split('/')
        pattern = r"Test Case '-\[" + re.escape(target + '.' + cls + ' ' + method) + r"\]' passed"
        log = (root / (label + '.log')).read_text()
        if len(re.findall(pattern, log)) != 1 or 'Restarting after unexpected' in log:
            raise RuntimeError('Selected native case identity or complete first execution differs')

    def welcome(label):
        observed = action('inspect', current)
        visible = any(w.get('name') == 'Welcome to MostlyText' and w.get('kCGWindowIsOnscreen')
                      for w in observed.get('windows', []))
        key = command(label + '-acknowledgement', ['defaults', 'read', 'app.mostlytext.MostlyText',
                                                  'com.joncallim.macdown2.hasCompletedFirstRun'])
        absent = key['returncode'] == 1 and 'does not exist' in key['stderr']
        false = key['returncode'] == 0 and key['stdout'].strip() == '0'
        record.setdefault('welcome', {})[label] = {'inspection': observed, 'acknowledgement': key,
                                                 'visible': visible, 'acknowledged': not (absent or false)}
        persist()
        if not observed.get('window_metadata_available') or not visible or key['timed_out'] or not (absent or false):
            raise RuntimeError('Actual fresh Welcome or unacknowledged state was not preserved')

    def verify_saved(label):
        target = Path(receipt['cli_stdin']['saved'])
        original = read_regular(receipt['cli_stdin']['oracle'])
        actual = read_regular(target)
        record.setdefault('physical_saved', {})[label] = {'path': str(target), 'bytes': len(actual), 'sha256': sha(target),
                                                        'matches_original_oracle': actual == original}
        persist()
        if actual != original:
            raise RuntimeError('Actual saved stdin bytes differ from their independent oracle')

    def verify_inputs(label):
        checked(label, [sys.executable, '.github/scripts/prepare-hosted-cli-stdin-save.py', root, '--phase', 'verify'], timeout=60)

    try:
        verify_inputs('before-positive-input-verification')
        checked('product-absent-before-positive', [root / 'product-absence'])
        ui_phase('positive', 'HostedFocusDriverTests/PublicFocusTests/testBenignInputControl')
        record['criteria']['genuine_control'] = True
        facts = json.loads(checked('actual-gui', [root / 'host-facts'])['stdout'])
        record['actual_gui'] = facts
        persist()
        if facts['keyboard_input_source'] != 'com.apple.keylayout.US':
            raise RuntimeError('Actual keyboard input source is not the reviewed US layout')
        checked('product-absent-before-cold-client', [root / 'product-absence'])
        cold = command('untrusted-cold-file', [receipt['public_cli'], receipt['source_file']])
        if cold['returncode'] != 5 or cold['timed_out']:
            raise RuntimeError('The ad-hoc cold launch did not refuse with the original unavailable result')
        checked('product-absent-after-cold-client', [root / 'product-absence'])
        record['criteria']['untrusted_cold_refused_without_launch'] = True
        verify_inputs('after-cold-input-verification')
        current = action('launch')
        (root / 'current-application.json').write_text(json.dumps(current, indent=2) + '\n')
        import hashlib
        runtime = Path(subprocess.check_output(['getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip()).resolve()
        endpoint = runtime / ('mt-' + hashlib.sha256(b'app.mostlytext.MostlyText').hexdigest()[:24]) / 's'
        deadline = time.monotonic() + 10
        attempts = []
        while time.monotonic() < deadline:
            value = probe_endpoint(endpoint, current['pid'], min(0.05, max(0.001, deadline - time.monotonic())))
            attempts.append(value)
            if value['ready']:
                break
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        record['live_endpoint'] = {'pid': current['pid'], 'attempts': attempts, 'application_frames_sent': 0}
        persist()
        if not attempts or not attempts[-1]['ready']:
            raise RuntimeError('No matching actual live peer within the original ten seconds')
        welcome('before-stdin')
        payload = read_regular(receipt['cli_stdin']['oracle'])
        checked('ordinary-public-implicit-stdin', [receipt['public_cli']], payload)
        welcome('after-stdin')
        record['criteria']['public_stdin_acknowledged_with_welcome_preserved'] = True
        ui_phase('stdin-save', 'HostedFocusDriverTests/CLIStdinTests/testOrdinaryStdinDocumentSavesExactUTF8Bytes')
        verify_saved('before-quit')
        record['criteria']['actual_editor_and_saved_bytes'] = True
        observed = action('inspect', current)
        if observed['pid'] != current['pid'] or observed['birth'] != current['birth']:
            raise RuntimeError('Actual normal process identity changed')
        verify_inputs('before-normal-quit-input-verification')
        ending = action('terminate', current)
        if not ending['terminated']:
            raise RuntimeError('Normal termination did not finish')
        current = None
        record['criteria']['normal_identity_bound_quit'] = True
        checked('product-absent-after-normal-quit', [root / 'product-absence'])
        verify_saved('after-normal-quit')
        verify_inputs('after-normal-quit-input-verification')
        record['criteria']['unchanged_inputs_after_normal_quit'] = True
    except Exception as error:
        record['errors'].append({'type': type(error).__name__, 'message': str(error)[:4096]})
    finally:
        if current is not None:
            try:
                action('inspect', current)
                action('cleanup', current)
            except Exception as error:
                record.setdefault('cleanup_errors', []).append(str(error)[:4096])
        record['passed'] = len(record['criteria']) == 6 and all(record['criteria'].values()) and not record['errors']
        persist()
    if not record['passed']:
        raise RuntimeError('The first public stdin/save journey failed; original evidence retained')


if __name__ == '__main__':
    main()
