#!/usr/bin/env python3
"""Record only actual own provider logs in the working host context; never signal a provider."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import selectors
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('jsc_preparation', Path(__file__).with_name('prepare-quicklook-jsc-probe.py'))
PREP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREP)


def publish(root, messages, sequence, checkout):
    if type(sequence) is not int or not 0 <= sequence < 128 or not isinstance(messages, list) or not all(isinstance(x, str) for x in messages):
        raise RuntimeError('Invalid or excessive observer snapshot')
    record = {'kind': 'mostlytext-qljsc-host-observer', 'checkout': checkout, 'sequence': sequence, 'messages': messages}
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


def process_state(pid, expected_path, run=subprocess.run, existence=os.kill):
    result = run(['/bin/ps', '-p', str(pid), '-o', 'pid=', '-o', 'uid=', '-o', 'comm='],
                 capture_output=True, timeout=1)
    if len(result.stdout) > 2048 or result.stderr:
        raise RuntimeError('Exact XPC process inspection produced unexpected output')
    if result.returncode == 1 and not result.stdout:
        try:
            existence(pid, 0)  # Signal zero checks existence; it cannot terminate the service.
        except ProcessLookupError:
            return 'absent'
        except PermissionError:
            return 'wrong'
        return 'wrong'
    parts = result.stdout.decode('utf-8').strip().split(maxsplit=2)
    if result.returncode != 0 or len(parts) != 3:
        return 'wrong'
    try:
        found_pid, uid = int(parts[0]), int(parts[1])
    except ValueError:
        return 'wrong'
    return 'expected' if (found_pid, uid, parts[2]) == (pid, 501, expected_path) else 'wrong'


def publish_hold_process(root, hold, samples, checkout):
    if not 1 <= len(samples) <= 96:
        raise RuntimeError('Invalid bounded XPC host process sample count')
    folder = root / 'hold-process-journal'
    folder.mkdir(mode=0o700, exist_ok=True)
    row = {'kind': 'mostlytext-qlxpc-process-sample', 'checkout': checkout,
           'request_id': hold['request_id'], 'provider_pid': hold['provider_pid'],
           'service_pid': hold['service_pid'], 'sample': samples[-1]}
    row_raw = (json.dumps(row, sort_keys=True) + '\n').encode()
    journal = folder / f'{len(samples) - 1:03d}.json'
    with journal.open('xb') as stream:
        stream.write(row_raw)
    journal.chmod(0o600)
    snapshot = dict(hold, kind='mostlytext-qlxpc-host-process', checkout=checkout, samples=samples)
    raw = (json.dumps(snapshot, sort_keys=True) + '\n').encode()
    if len(raw) > 128 * 1024:
        raise RuntimeError('XPC host process observation exceeded128KiB')
    temporary = root / '.hold-process-observer-next.json'
    with temporary.open('xb') as stream:
        stream.write(raw)
    temporary.chmod(0o600)
    os.replace(temporary, root / 'hold-process-observer.json')
    return {'file': str(journal.relative_to(root)), 'bytes': len(row_raw),
            'sha256': hashlib.sha256(row_raw).hexdigest()}


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
    stop_deadline = None
    stop_received = None

    def stop(_signum, _frame):
        nonlocal stopping, stop_deadline, stop_received
        stopping = True
        if stop_deadline is None:
            stop_received = time.monotonic()
            stop_deadline = time.monotonic() + 2

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    control = root / 'observer-control'
    control_digest = PREP.digest(control)
    if receipt['compiled_before_test']['observer_control']['sha256'] != control_digest:
        raise RuntimeError('Actual control binary changed before channel admission')
    record = {'checkout': checkout, 'pid': os.getpid(), 'command': sys.argv, 'snapshots': [],
              'errors': [], 'mode': 'live-ndjson', 'stream_command': PREP.STREAM_COMMAND,
              'control_sha256': control_digest, 'nonce': str(uuid.uuid4()).upper(), 'control_attempts': [],
              'stream_forced_cleanup': False, 'stream_unexpected_exit': False,
              'stopped_after_ui': False, 'timed_out': False}
    started = time.monotonic()
    record['started_monotonic'] = started
    stream = None
    raw = bytearray()
    errors = bytearray()
    pending = bytearray()
    messages = []
    position = 0
    admitted = False
    next_pulse = started
    hold = None
    hold_samples = []
    hold_journal = []
    next_hold_sample = None
    hold_stop_at = None
    try:
        stream = subprocess.Popen(PREP.STREAM_COMMAND, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        record['stream_pid'] = stream.pid
        with selectors.DefaultSelector() as selector:
            for pipe, label in [(stream.stdout, 'stdout'), (stream.stderr, 'stderr')]:
                os.set_blocking(pipe.fileno(), False)
                selector.register(pipe, selectors.EVENT_READ, label)
            while selector.get_map():
                now = time.monotonic()
                if stop_deadline is not None and now >= stop_deadline:
                    raise RuntimeError('Actual stream did not drain within owned stop bound')
                if stream.poll() is not None and not stopping:
                    record['stream_unexpected_exit'] = True
                    raise RuntimeError('Actual live log stream exited while UI observation was active')
                if now - started > 300:
                    record['timed_out'] = True
                    raise RuntimeError('Bounded host observer lifetime exceeded')
                if not admitted and not stopping:
                    if now - started >= 5:
                        raise RuntimeError('No genuine channel echo within unchanged startup bound')
                    if now >= next_pulse:
                        if len(record['control_attempts']) >= 25 or PREP.digest(control) != control_digest:
                            raise RuntimeError('Control admission budget or binary identity changed')
                        command = [str(control), record['nonce']]
                        attempt = {'command': command, 'started_monotonic': now}
                        record['control_attempts'].append(attempt)
                        result = subprocess.run(command, capture_output=True, timeout=3)
                        attempt.update(returncode=result.returncode, completed_monotonic=time.monotonic(),
                                       stdout=result.stdout.decode('utf-8'), stderr=result.stderr.decode('utf-8'))
                        if result.returncode or result.stdout or result.stderr:
                            raise RuntimeError('Actual control emitter failed or emitted unexpected console bytes')
                        next_pulse = time.monotonic() + 0.2
                if stopping and stream.poll() is None:
                    stream.terminate()
                for key, _mask in selector.select(timeout=0.05):
                    chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    if key.data == 'stderr':
                        errors.extend(chunk)
                        if len(errors) > 256 * 1024:
                            raise RuntimeError('Actual stream stderr exceeded256KiB')
                        continue
                    raw.extend(chunk)
                    if len(raw) > 1024 * 1024:
                        raise RuntimeError('Actual live stream exceeded1MiB')
                    pending.extend(chunk)
                    while b'\n' in pending:
                        line, _, remainder = pending.partition(b'\n')
                        pending[:] = remainder
                        position += len(line) + 1
                        value = PREP.parse_live_record(line)
                        changed = False
                        if PREP.is_control_echo(value, record['nonce']) and not admitted:
                            if time.monotonic() - started >= 5:
                                raise RuntimeError('Genuine echo arrived after unchanged startup bound')
                            admitted = True
                            record['admitted_monotonic'] = time.monotonic()
                            changed = True
                        elif value is not None and value['subsystem'] == PREP.PROVIDER_SUBSYSTEM:
                            if not admitted:
                                raise RuntimeError('Actual provider record preceded channel admission')
                            messages.append(value['eventMessage'])
                            changed = True
                            hold_admission = re.fullmatch(r'QL_XPC_HOLD admitted id=(\d+) provider=(\d+) service=(\d+) ready=([0-9.]+)',
                                                         value['eventMessage'])
                            if hold_admission:
                                if hold is not None or any(int(hold_admission[index]) <= 0 for index in (1, 2, 3)):
                                    raise RuntimeError('Duplicate or invalid XPC hold admission')
                                hold = {'request_id': int(hold_admission[1]), 'provider_pid': int(hold_admission[2]),
                                        'service_pid': int(hold_admission[3]),
                                        'provider_path': str(root / 'build/Build/Products/Release/QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex/Contents/MacOS/QLReplyProbeProvider'),
                                        'service_path': str(root / 'build/Build/Products/Release/QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex/Contents/XPCServices/QLReplyProbeXPCService.xpc/Contents/MacOS/QLReplyProbeXPCService')}
                                next_hold_sample = time.monotonic()
                            hold_invalidation = re.fullmatch(r'QL_XPC_HOLD invalidated id=(\d+) provider=(\d+) service=(\d+) at=([0-9.]+)',
                                                             value['eventMessage'])
                            if hold_invalidation:
                                if (hold is None or hold_stop_at is not None
                                        or tuple(int(hold_invalidation[index]) for index in (1, 2, 3))
                                        != (hold['request_id'], hold['provider_pid'], hold['service_pid'])):
                                    raise RuntimeError('Unowned or duplicate XPC hold invalidation')
                                hold_stop_at = float(hold_invalidation[4]) + 3.3
                        if changed:
                            row = publish(root, messages, len(record['snapshots']), checkout)
                            row['stream_position'] = position
                            record['snapshots'].append(row)
                    if len(pending) > 128 * 1024:
                        raise RuntimeError('Incomplete live record exceeded128KiB')
                if (hold is not None and not stopping and time.monotonic() >= next_hold_sample
                        and (hold_stop_at is None or not hold_samples or hold_samples[-1]['uptime'] < hold_stop_at)):
                    if len(hold_samples) >= 96:
                        raise RuntimeError('XPC host process sample budget exhausted before UI completed')
                    sampled = time.monotonic()
                    service = process_state(hold['service_pid'], hold['service_path'])
                    provider = process_state(hold['provider_pid'], hold['provider_path'])
                    checked = time.monotonic()
                    row = {'index': len(hold_samples), 'uptime': sampled, 'check_uptime': checked,
                           'service': service, 'provider': provider}
                    hold_samples.append(row)
                    hold_journal.append(publish_hold_process(root, hold, hold_samples, checkout))
                    next_hold_sample = checked + 0.075
        if pending or not admitted:
            raise RuntimeError('Incomplete actual stream or missing startup echo')
        if any(not line.startswith('Filtering the log data using ') for line in errors.decode('utf-8').splitlines()):
            raise RuntimeError('Actual stream reported unexpected stderr')
        if not stopping:
            raise RuntimeError('Actual stream ended without post-UI observer stop')
        record['stopped_after_ui'] = True
    except BaseException as error:
        record['errors'].append(repr(error))
        raise
    finally:
        if stream is not None:
            if stream.poll() is None:
                stream.terminate()
            try:
                stream.wait(timeout=3)
            except subprocess.TimeoutExpired:
                record['stream_forced_cleanup'] = True
                stream.kill()
                stream.wait(timeout=1)
            record['stream_returncode'] = stream.returncode
            stream.stdout.close()
            stream.stderr.close()
        (root / 'observer-stream.log').write_bytes(raw)
        (root / 'observer-stream-errors.txt').write_bytes(errors)
        record['stream_bytes'] = len(raw)
        record['stream_sha256'] = hashlib.sha256(raw).hexdigest()
        record['stop_signal_monotonic'] = stop_received
        record['finished_monotonic'] = time.monotonic()
        record['elapsed_seconds'] = time.monotonic() - started
        if hold is not None:
            record['hold_process'] = {'request_id': hold['request_id'], 'provider_pid': hold['provider_pid'],
                                      'service_pid': hold['service_pid'], 'samples': hold_journal,
                                      'snapshot_sha256': hashlib.sha256((root / 'hold-process-observer.json').read_bytes()).hexdigest()
                                      if (root / 'hold-process-observer.json').exists() else None}
        (root / 'observer-result.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
