#!/usr/bin/env python3
"""Record only actual own provider logs in the working host context; never signal a provider."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import selectors
import subprocess
import sys
import time
import uuid

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
                        if changed:
                            row = publish(root, messages, len(record['snapshots']), checkout)
                            row['stream_position'] = position
                            record['snapshots'].append(row)
                    if len(pending) > 128 * 1024:
                        raise RuntimeError('Incomplete live record exceeded128KiB')
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
        (root / 'observer-result.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
