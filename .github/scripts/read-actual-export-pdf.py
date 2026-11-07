#!/usr/bin/env python3
"""Diagnose immutable failed canary bytes only on the existing guarded hosted worker."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path('/Users/runner/work/_temp/mostlytext-focus')
PACKET = Path('planning/downstream/evidence/ordinary-export-pdf-original-failure-2026-11-08')
PDF_SHA = 'ce2b5cc91a8a774c894c43d0f1fe56d4f95cce32171a80c8c2b0f70785af0ae6'
ORIGINAL_VALIDATOR_SHA = 'a3456a0056f9f2883dbeb829cd03ee1bc43c11aa617c3c9bec5a0da5e327f117'


def decoded_record(row):
    name = row['file']
    if Path(name).name != name or not name.endswith('.gz') or not 0 < row['bytes'] < 4 * 1024 * 1024:
        raise RuntimeError('Refuse an unbounded or redirected original evidence record')
    path = PACKET / name
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('Original evidence must be an immutable regular source file')
    # Committed packet files are bounded as well as their exact uncompressed records.
    if path.stat().st_size > 4 * 1024 * 1024:
        raise RuntimeError('Oversized compressed original evidence')
    with gzip.open(path, 'rb') as stream:
        raw = stream.read(row['bytes'] + 1)
    if len(raw) != row['bytes'] or hashlib.sha256(raw).hexdigest() != row['sha256']:
        raise RuntimeError('Original evidence differs from its exact first record')
    return raw


def main():
    if sys.flags.optimize or sys.argv[1:] not in [['prepare'], ['observe']]:
        raise RuntimeError('Select the fixed nonoptimized diagnostic phase')
    spec = importlib.util.spec_from_file_location('actual_guard', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    guard.check_host(ROOT)
    packet = json.loads((PACKET / 'manifest.json').read_bytes())
    if (packet['source'] != '734db2f2cd083c040365919134163b55ed57f41f' or packet['native_run'] != 42424848502
            or packet['whole_result'] != 'failure' or len(packet['records']) != 16):
        raise RuntimeError('This diagnostic only reads the exact retained failed first')
    records = {r['original_name']: decoded_record(r) for r in packet['records']}
    raw = records['ordinary-export.pdf']
    if len(raw) != 16424 or hashlib.sha256(raw).hexdigest() != PDF_SHA:
        raise RuntimeError('Refuse any substitute PDF or later successful fixture')
    original = Path('.github/hosted-export-acceptance/ValidatePDF.swift')
    if (hashlib.sha256(original.read_bytes()).hexdigest() != ORIGINAL_VALIDATOR_SHA
            or original.read_bytes() != records['ValidatePDF.swift']):
        raise RuntimeError('Original failed guard must remain unchanged')
    path = ROOT / 'pdf-readback-receipt.json'
    inputs = ['.github/scripts/read-actual-export-pdf.py', '.github/hosted-export-acceptance/ReadActualPDF.swift',
              '.github/hosted-export-acceptance/ValidatePDF.swift', '.github/scripts/prepare-hosted-public-focus.py',
              '.github/workflows/ordinary-export-pdf-readback.yml', str(PACKET / 'manifest.json')]
    source = {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in inputs}
    if sys.argv[1] == 'prepare':
        if ROOT.exists() or ROOT.is_symlink():
            raise RuntimeError('The fixed diagnostic root must be fresh')
        (ROOT / 'documents').mkdir(parents=True, mode=0o700)
        (ROOT / 'documents/ordinary-export.pdf').write_bytes(raw)
        record = {'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                  'source_sha256': source, 'pdf_sha256': PDF_SHA, 'diagnostic_only': True, 'qualification_candidate': False,
                  'app_GUI_launches': 0, 'scope': 'Read-only immutable original failed canary; not export qualification'}
        path.write_text(json.dumps(record, indent=2) + '\n')
        return
    record = json.loads(path.read_bytes())
    if record['source_sha256'] != source or (ROOT / 'documents/ordinary-export.pdf').read_bytes() != raw:
        raise RuntimeError('Original source or PDF bytes changed before native readback')
    record['compiled_sha256'] = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest()
                                 for n in ['validate-export-pdf', 'read-actual-export-pdf']}
    path.write_text(json.dumps(record, indent=2) + '\n')
    baseline = subprocess.run([str(ROOT / 'validate-export-pdf'), str(ROOT / 'documents/ordinary-export.pdf')],
                              capture_output=True, text=True, timeout=30)
    record['actual_original_guard'] = {'returncode': baseline.returncode, 'stdout': baseline.stdout[:4096],
                                      'stderr': baseline.stderr[:4096]}
    path.write_text(json.dumps(record, indent=2) + '\n')
    if baseline.returncode != -5 or 'ValidateActualExportPDF.Refusal.invalid' not in baseline.stderr:
        raise RuntimeError('Original guard has a different outcome; retain it without inventing a cause')
    observed = subprocess.run([str(ROOT / 'read-actual-export-pdf')], capture_output=True, text=True, timeout=30)
    record['actual_readback'] = {'returncode': observed.returncode, 'stdout': observed.stdout[:4096], 'stderr': observed.stderr[:4096]}
    path.write_text(json.dumps(record, indent=2) + '\n')
    if observed.returncode != 0:
        raise RuntimeError('Actual PDFKit readback failed; no predicate/fidelity inference allowed')
    result = json.loads((ROOT / 'actual-pdf-readback.json').read_bytes())
    if (result['sha256'] != PDF_SHA or result['diagnostic_only'] is not True or result['qualification_candidate'] is not False
            or (ROOT / 'documents/ordinary-export.pdf').read_bytes() != raw):
        raise RuntimeError('Readback did not preserve the original diagnostic scope/bytes')
    record['readback_complete'] = True
    path.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
