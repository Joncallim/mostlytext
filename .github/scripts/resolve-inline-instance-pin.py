#!/usr/bin/env python3
"""Guarded deliberate SwiftPM resolution only; never build or launch the product."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path('/Users/runner/work/_temp/mostlytext-focus')
PACKAGE = Path('MacDown2/Packages/MacDownKit')
OLD = 'ff74cf54c278b451b2c59387dd00315830266a36'
NEW = '6eba6da7d2d27d85560b956057fd98badd9b3495'
MANIFEST_SHA = '4977d8018116e76b62a2c33a3836a890c5b0fa8d6f8ad4c2df33384ceca7c0a7'
LOCK_SHA = '716882ac8bc84aae7f5fa0c8b9ea627d9a6330ba24688f486fc690cd710be176'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def validate_pins(before, after):
    if before['version'] != after['version'] or len(before['pins']) != 24 or len(after['pins']) != 24:
        raise ValueError('The exact 24-pin closure must remain')
    old = {r['identity']: r for r in before['pins']}
    new = {r['identity']: r for r in after['pins']}
    if len(old) != 24 or len(new) != 24 or old.keys() != new.keys():
        raise ValueError('Duplicate, added or removed package identity')
    for identity, original in old.items():
        expected = json.loads(json.dumps(original))
        if identity == 'textual':
            if expected['location'] != 'https://github.com/Joncallim/textual' or expected['state'] != {'revision': OLD}:
                raise ValueError('Require the exact old immutable Textual')
            expected['state'] = {'revision': NEW}
        if new[identity] != expected:
            raise ValueError('Unexpected dependency change: ' + identity)
    if 'textual' not in old:
        raise ValueError('Textual omitted')


def main():
    if sys.flags.optimize or sys.argv[1:]:
        raise ValueError('Fixed nonoptimized hosted resolution only')
    spec = importlib.util.spec_from_file_location('fixed_host', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    guard.check_host(ROOT)
    manifest = (PACKAGE / 'Package.swift').read_bytes()
    lock = (PACKAGE / 'Package.resolved').read_bytes()
    if sha(manifest) != MANIFEST_SHA or sha(lock) != LOCK_SHA or manifest.count(OLD.encode()) != 1:
        raise ValueError('Original package input differs from the reviewed canonical baseline')
    candidate = manifest.replace(OLD.encode(), NEW.encode())
    if ROOT.exists() or ROOT.is_symlink():
        raise ValueError('Owned resolver output must be fresh')
    ROOT.mkdir(mode=0o700)
    for name, raw in [('Package.original.swift', manifest), ('Package.candidate.swift', candidate), ('Package.original.resolved', lock)]:
        (ROOT / name).write_bytes(raw)
    sources = ['.github/scripts/resolve-inline-instance-pin.py', '.github/scripts/test-inline-instance-pin-resolution.py',
               '.github/scripts/prepare-hosted-public-focus.py', '.github/workflows/preview-grant-probe.yml',
               str(PACKAGE / 'Package.swift'), str(PACKAGE / 'Package.resolved')]
    record = {'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              'source_sha256': {p: sha(Path(p).read_bytes()) for p in sources},
              'old_revision': OLD, 'new_revision': NEW, 'candidate_manifest_sha256': sha(candidate),
              'host': {'uid': os.getuid(), 'effective_uid': os.geteuid(), 'home': str(Path.home()), 'machine': platform.machine(),
                       'os': subprocess.check_output(['sw_vers'], text=True), 'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True)},
              'command': ['swift', 'package', '--package-path', str(PACKAGE), 'resolve'],
              'product_builds': 0, 'app_GUI_engine_launches': 0,
              'scope': 'Deliberate immutable dependency resolution only; no product or native qualification'}
    receipt = ROOT / 'pin-resolution-receipt.json'
    receipt.write_text(json.dumps(record, indent=2) + '\n')
    try:
        (PACKAGE / 'Package.swift').write_bytes(candidate)
        with (ROOT / 'resolve.stdout').open('wb') as stdout, (ROOT / 'resolve.stderr').open('wb') as stderr:
            result = subprocess.run(record['command'], stdout=stdout, stderr=stderr, timeout=600)
        record['resolve_returncode'] = result.returncode
        receipt.write_text(json.dumps(record, indent=2) + '\n')
        if result.returncode:
            raise ValueError('Actual SwiftPM resolve failed')
        actual = (PACKAGE / 'Package.resolved').read_bytes()
        (ROOT / 'Package.resolved').write_bytes(actual)
        validate_pins(json.loads(lock), json.loads(actual))
        record['actual_lock_sha256'] = sha(actual)
        record['other_23_pins_unchanged'] = True
        record['actual_resolve_complete'] = True
    finally:
        (PACKAGE / 'Package.swift').write_bytes(manifest)
        (PACKAGE / 'Package.resolved').write_bytes(lock)
        if (PACKAGE / 'Package.swift').read_bytes() != manifest or (PACKAGE / 'Package.resolved').read_bytes() != lock:
            raise ValueError('Failed to restore exact original checkout inputs')
        record['exact_original_source_restored'] = True
        receipt.write_text(json.dumps(record, indent=2) + '\n')
    print('Actual SwiftPM lock captured; one Textual revision changed, other 23 pins unchanged')


if __name__ == '__main__':
    main()
