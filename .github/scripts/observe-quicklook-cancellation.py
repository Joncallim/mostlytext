#!/usr/bin/env python3
"""Record only actual own provider logs in the working host context; never signal a provider."""
import hashlib
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


def publish(root, messages, sequence, checkout):
    if type(sequence) is not int or not 0 <= sequence < 128 or not isinstance(messages, list) or not all(isinstance(x, str) for x in messages):
        raise RuntimeError('Invalid or excessive observer snapshot')
    record = {'kind': 'mostlytext-qlcancel-host-observer', 'checkout': checkout, 'sequence': sequence, 'messages': messages}
    raw = (json.dumps(record, sort_keys=True) + '\n').encode()
    if len(raw) > 128 * 1024:
        raise RuntimeError('Host observer snapshot exceeded128KiB')
    folder = root / 'observer-journal'
    folder.mkdir(mode=0o700, exist_ok=True)
    target = folder / (f'{sequence:03d}.json')
    with target.open('xb') as stream:
        stream.write(raw)
    target.chmod(0o600)
    temporary = root / '.provider-observer-next.json'
    with temporary.open('xb') as stream:
        stream.write(raw)
    temporary.chmod(0o600)
    os.replace(temporary, root / 'provider-observer.json')
    return {'file': str(target.relative_to(root)), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def main():
    PREP.require_standard_python()
    if len(sys.argv) != 2:
        raise RuntimeError('One exact generated probe root is required')
    root = Path(sys.argv[1]).resolve()
    PREP.require_host(root)
    receipt = json.loads((root / 'receipt.json').read_text())
    checkout = PREP.command(['git', 'rev-parse', 'HEAD'])
    if receipt['checkout'] != checkout:
        raise RuntimeError('Host observer checkout differs from actual compiled fixture')
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    record = {'checkout': checkout, 'pid': os.getpid(), 'command': sys.argv, 'snapshots': [],
              'errors': [], 'successful_log_queries': 0, 'stopped_after_ui': False, 'timed_out': False}
    previous = None
    started = time.monotonic()
    try:
        while not stopping:
            if time.monotonic() - started > 300:
                record['timed_out'] = True
                raise RuntimeError('Bounded host observer lifetime exceeded')
            command = ['/usr/bin/log', 'show', '--last', '1m', '--style', 'json', '--predicate',
                       'subsystem == "app.mostlytext.qlcancelprobe"']
            result = subprocess.run(command, capture_output=True, timeout=3)
            if stopping:
                record['last_query_during_observer_stop'] = {'command': command, 'returncode': result.returncode}
                break
            if result.returncode:
                (root / 'observer-command-errors.txt').write_bytes(result.stdout + result.stderr)
                raise RuntimeError('Actual host log command failed: ' + str(result.returncode))
            if len(result.stdout) > 256 * 1024:
                raise RuntimeError('Actual own provider log output exceeded256KiB')
            values = json.loads(result.stdout)
            if not isinstance(values, list) or not all(isinstance(x, dict) for x in values):
                raise RuntimeError('Actual provider log output has an unknown schema')
            messages = [x.get('eventMessage', '') for x in values]
            record['successful_log_queries'] += 1
            if messages != previous:
                row = publish(root, messages, len(record['snapshots']), checkout)
                row.update(command=command, command_returncode=0)
                record['snapshots'].append(row)
                previous = messages
            time.sleep(0.2)
        record['stopped_after_ui'] = True
    except BaseException as error:
        record['errors'].append(repr(error))
        raise
    finally:
        record['elapsed_seconds'] = time.monotonic() - started
        (root / 'observer-result.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
