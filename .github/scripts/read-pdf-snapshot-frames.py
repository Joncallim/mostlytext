#!/usr/bin/env python3
"""Fixed disposable-host WebKit canvas comparison, never product acceptance."""
import hashlib
import importlib.util
import json
import resource
from pathlib import Path
import subprocess
import sys

ROOT = Path('/Users/runner/work/_temp/mostlytext-focus')
INPUT_SHA = '7e6cab53fe7ce75713efb9d50aa15c685f8824b8ff59428a8d16930ec70d2d17'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sys.flags.optimize or sys.argv[1:] not in [['prepare'], ['observe']]:
        raise RuntimeError('Choose one fixed nonoptimized native diagnostic phase')
    spec = importlib.util.spec_from_file_location('guard', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
    guard.check_host(ROOT)
    spec = importlib.util.spec_from_file_location('original', Path(__file__).with_name('read-actual-export-pdf.py'))
    original = importlib.util.module_from_spec(spec); spec.loader.exec_module(original)
    manifest = original.PACKET / 'manifest.json'
    packet = json.loads(manifest.read_bytes())
    row = next(r for r in packet['records'] if r['original_name'] == 'ordinary-export.html')
    data = original.decoded_record(row)
    if len(data) != 6978 or hashlib.sha256(data).hexdigest() != INPUT_SHA:
        raise RuntimeError('Require the exact immutable original own canary HTML')
    files = ['.github/hosted-export-acceptance/ReadSnapshotFrames.swift',
             'MacDown2/MacDown2/PDFSnapshotFallback.swift', 'MacDown2/MacDown2/PDFExportAdapter.swift',
             '.github/scripts/read-pdf-snapshot-frames.py', '.github/scripts/read-actual-export-pdf.py',
             '.github/scripts/prepare-hosted-public-focus.py', '.github/workflows/pdf-snapshot-frames.yml', str(manifest)]
    inputs = {p: sha(Path(p)) for p in files}
    path = ROOT / 'snapshot-frame-receipt.json'
    if sys.argv[1] == 'prepare':
        if ROOT.exists() or ROOT.is_symlink(): raise RuntimeError('Require fresh fixed diagnostic root')
        ROOT.mkdir(mode=0o700)
        (ROOT / 'original.html').write_bytes(data)
        record = {'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                  'source_sha256': inputs, 'input_sha256': INPUT_SHA, 'diagnostic_only': True,
                  'qualification_candidate': False, 'product_app_launches': 0,
                  'native_scope': 'NSApplication prohibited activation and WebKit on disposable hosted machine only'}
        path.write_text(json.dumps(record, indent=2) + '\n'); return
    record = json.loads(path.read_bytes())
    if record['source_sha256'] != inputs or (ROOT / 'original.html').read_bytes() != data:
        raise RuntimeError('Native diagnostic sources or original HTML changed')
    binary = ROOT / 'read-snapshot-frames'
    record['compiled_sha256'] = sha(binary)
    path.write_text(json.dumps(record, indent=2) + '\n')
    # This controller exits after observation; the limit affects only this fixed phase and its native child.
    resource.setrlimit(resource.RLIMIT_FSIZE, (4 * 1024 * 1024, 4 * 1024 * 1024))
    try:
        with (ROOT / 'native-stdout.log').open('wb') as stdout, (ROOT / 'native-stderr.log').open('wb') as stderr:
            result = subprocess.run([str(binary)], stdout=stdout, stderr=stderr, timeout=150)
        record['native_returncode'] = result.returncode
        record['timed_out'] = False
    except subprocess.TimeoutExpired:
        record['timed_out'] = True
        raise
    finally:
        record['output_sha256'] = {p.name: sha(p) for p in ROOT.iterdir()
                                   if p.is_file() and p.name != path.name}
        path.write_text(json.dumps(record, indent=2) + '\n')
    if record['native_returncode'] != 0:
        raise RuntimeError('Native mechanism comparison failed; preserve first outcome without inference')
    observed = json.loads((ROOT / 'snapshot-frame-observations.json').read_bytes())
    if (observed['diagnostic_only'] is not True or observed['qualification_candidate'] is not False
            or observed['input_sha256'] != INPUT_SHA
            or [r['case'] for r in observed['completed_cases']] != ['original', 'paper', 'minimal']):
        raise RuntimeError('Incomplete fixed native comparison')
    record['complete_comparison'] = True
    path.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
