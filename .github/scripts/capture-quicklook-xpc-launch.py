#!/usr/bin/env python3
"""Retain a short host-system log window around the private XPC Finder request."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys

sys.dont_write_bytecode = True

SERVICE = 'app.mostlytext.QLReplyProbe.XPCService'
PROVIDER_SUBSYSTEM = 'app.mostlytext.qljscprobe'
PROVIDER_EXECUTABLE = 'QLReplyProbeProvider'
SYSTEM_PROCESSES = frozenset({'launchd', 'xpcproxy', 'amfid'})
MAX_LOG_BYTES = 4 * 1024 * 1024
MAX_LOG_EVENTS = 12000
PREDICATE = '(process == "launchd") OR (process == "xpcproxy") OR (process == "amfid")'
BEGIN = re.compile(r'QL_XPC_PROBE begin id=3 provider=(\d+) start=([0-9.]+)\Z')


def timestamp(value):
    if not isinstance(value, str):
        raise RuntimeError('Missing actual log timestamp')
    result = dt.datetime.fromisoformat(value)
    if result.tzinfo is None:
        raise RuntimeError('Actual log timestamp lacks timezone')
    return result


def request_window(events):
    if not isinstance(events, list):
        raise RuntimeError('Actual provider log is not an event array')
    beginnings = []
    for event in events:
        if not isinstance(event, dict) or event.get('subsystem') != PROVIDER_SUBSYSTEM:
            continue
        match = BEGIN.fullmatch(event.get('eventMessage', ''))
        if match is None:
            continue
        if (Path(event.get('processImagePath', '')).name != PROVIDER_EXECUTABLE
                or event.get('processID') != int(match[1])):
            raise RuntimeError('XPC begin lacks the actual provider process identity')
        beginnings.append(timestamp(event.get('timestamp')))
    if len(beginnings) != 1:
        raise RuntimeError('Require one actual XPC Finder request before system-log capture')
    beginning = beginnings[0]
    # The failed connection returned in under a millisecond; allow for nearby
    # launch and admission messages, then retain no other Finder test window.
    start = (beginning - dt.timedelta(seconds=2)).replace(microsecond=0)
    end = (beginning + dt.timedelta(seconds=4)).replace(microsecond=0) + dt.timedelta(seconds=1)
    return beginning, start, end


def log_command(start, end):
    if not 0 < (end - start).total_seconds() <= 8:
        raise RuntimeError('XPC system-log window exceeds eight seconds')
    utc = dt.timezone.utc
    return ['/usr/bin/log', 'show', '--info', '--no-pager', '--style', 'json', '--timezone', 'UTC',
            '--start', start.astimezone(utc).strftime('%Y-%m-%d %H:%M:%S+0000'),
            '--end', end.astimezone(utc).strftime('%Y-%m-%d %H:%M:%S+0000'),
            '--predicate', PREDICATE]


def validate_system_events(raw, start, end):
    if len(raw) > MAX_LOG_BYTES:
        raise RuntimeError('XPC system-log capture exceeded four MiB')
    events = json.loads(raw)
    if not isinstance(events, list) or len(events) > MAX_LOG_EVENTS:
        raise RuntimeError('XPC system-log capture has invalid event count')
    for event in events:
        if not isinstance(event, dict) or Path(event.get('processImagePath', '')).name not in SYSTEM_PROCESSES:
            raise RuntimeError('XPC system-log capture included another process')
        when = timestamp(event.get('timestamp'))
        if not start <= when <= end:
            raise RuntimeError('XPC system-log capture included another time window')
    return len(events)


def capture(root, run=subprocess.run):
    events = json.loads((root / 'provider-events.json').read_bytes())
    beginning, start, end = request_window(events)
    command = log_command(start, end)
    result = run(command, capture_output=True, timeout=30)
    if len(result.stderr) > 32 * 1024:
        raise RuntimeError('XPC system-log stderr exceeded 32 KiB')
    (root / 'xpc-system-log-errors.txt').write_bytes(result.stderr)
    if result.returncode != 0:
        raise RuntimeError('XPC system-log query failed')
    count = validate_system_events(result.stdout, start, end)
    (root / 'xpc-system-events.json').write_bytes(result.stdout)
    return {'status': 'captured', 'service': SERVICE,
            'provider_begin': beginning.isoformat(), 'start': start.isoformat(), 'end': end.isoformat(),
            'query': command, 'events': count, 'bytes': len(result.stdout),
            'sha256': hashlib.sha256(result.stdout).hexdigest()}


def main():
    if len(sys.argv) != 1:
        raise RuntimeError('This private diagnostic accepts no path or command override')
    root = Path(os.environ.get('RUNNER_TEMP', '/absent')).resolve() / 'mostlytext-qljsc'
    if (os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.getuid() != 501 or os.geteuid() != 501
            or pwd.getpwuid(os.getuid()).pw_name != 'runner'
            or root != Path('/Users/runner/work/_temp/mostlytext-qljsc')):
        raise RuntimeError('Require exact private hosted Quick Look diagnostic context')
    try:
        record = capture(root)
    except BaseException as error:
        (root / 'xpc-system-capture.json').write_text(json.dumps({
            'status': 'failed', 'service': SERVICE, 'error': repr(error)}, indent=2) + '\n')
        raise
    (root / 'xpc-system-capture.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
