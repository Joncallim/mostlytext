#!/usr/bin/env python3
"""Fresh hosted snapshot admission with preserved historical canvas checks."""
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


def verify_candidate_rendering(root, observed):
    """Validate the archived 2026-11-08 canvas evidence only."""
    names = ['original', 'paper', 'minimal', 'boundary-original', 'boundary-paper', 'css-paper', 'css-boundary-paper']
    cases = observed.get('completed_cases')
    if not isinstance(cases, list) or [c.get('case') for c in cases] != names:
        raise RuntimeError('Require every unique original and candidate canvas control in order')
    rows = {c['case']: c for c in cases}

    def png(name, index):
        path = root / f'{name}-page-{index + 1}.png'
        if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 4 * 1024 * 1024:
            raise RuntimeError('Require bounded actual candidate/reference PNG bytes')
        return path.read_bytes()

    for candidate, reference, count in [('css-paper', 'original', 1), ('css-boundary-paper', 'boundary-original', 2)]:
        row = rows[candidate]; original = rows[reference]
        if (row['snapshot_media_box'][2] != 794 or len(row['pages']) != count
                or len(original['pages']) != 2):
            raise RuntimeError('Candidate narrowed layout, appended viewport blankness or trimmed authored space')
        for i in range(count):
            page, prior = row['pages'][i], original['pages'][i]
            if (type(page['index']) is not int or page['index'] != i or page['raw_text'] != prior['raw_text']
                    or type(page['actual_raster_nonwhite_pixels']) is not int
                    or page['actual_raster_nonwhite_pixels'] != prior['actual_raster_nonwhite_pixels']
                    or (i == 0 and (not page['raw_text'].strip() or page['actual_raster_nonwhite_pixels'] <= 0))
                    or png(candidate, i) != png(reference, i)):
                raise RuntimeError('Candidate changed actual text or pixels instead of only the unused canvas')


def verify_current_admission(root, observed):
    """Require fresh WebKit vector bytes and the production paper-only verdict."""
    names = ['original', 'paper', 'minimal', 'boundary-original',
             'boundary-paper', 'css-paper', 'css-boundary-paper']
    cases = observed.get('completed_cases')
    if not isinstance(cases, list) or [row.get('case') for row in cases] != names:
        raise RuntimeError('Require all seven fresh WebKit snapshot cases in order')
    paper = observed.get('paper_size')
    if (not isinstance(paper, list) or len(paper) != 2
            or any(type(value) not in (int, float) or value <= 0 for value in paper)):
        raise RuntimeError('Missing paper geometry')
    rows = {row['case']: row for row in cases}
    refused = 0
    for row in cases:
        name = row['case']
        path = root / f'{name}-snapshot.pdf'
        if (path.is_symlink() or not path.is_file()
                or not 0 < path.stat().st_size <= 4 * 1024 * 1024
                or path.stat().st_size != row.get('snapshot_bytes')
                or sha(path) != row.get('snapshot_sha256')):
            raise RuntimeError(name + ' lacks exact fresh WebKit snapshot bytes')
        box = row.get('snapshot_media_box')
        if (not isinstance(box, list) or len(box) != 4
                or any(type(value) not in (int, float) for value in box)
                or box[2] <= 0 or box[3] <= 0
                or not isinstance(row.get('raw_text'), str) or not row['raw_text'].strip()):
            raise RuntimeError(name + ' lacks source geometry or extractable text')
        paper_sized = abs(box[2] - paper[0]) < 1 and abs(box[3] - paper[1]) < 1
        expected = 'paper-preserved' if paper_sized else 'oversized-refused'
        if row.get('disposition') != expected:
            raise RuntimeError(name + ' has a publication verdict inconsistent with its geometry')
        refused += not paper_sized
    if refused == 0:
        raise RuntimeError('No oversized WebKit source exercised the refusal policy')
    for candidate, reference in [('css-paper', 'original'),
                                 ('css-boundary-paper', 'boundary-original')]:
        if ' '.join(rows[candidate]['raw_text'].split()) != ' '.join(rows[reference]['raw_text'].split()):
            raise RuntimeError(candidate + ' changed the authored text before PDF admission')


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
             'MacDown2/Packages/MacDownKit/Sources/ExportService/PDFCanvasStylesheet.swift',
             '.github/scripts/read-pdf-snapshot-frames.py', '.github/scripts/test-pdf-snapshot-result.py',
             '.github/scripts/test-actual-export-pdf-readback.py', '.github/scripts/read-actual-export-pdf.py',
             '.github/scripts/prepare-hosted-public-focus.py', '.github/workflows/pdf-snapshot-frames.yml', str(manifest)]
    files += subprocess.check_output(['git', 'ls-files', '--',
        'planning/downstream/evidence/pdf-scrollbar-prototype-qualified-2026-11-08'], text=True).splitlines()
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
            or [r['case'] for r in observed['completed_cases']] != ['original', 'paper', 'minimal', 'boundary-original', 'boundary-paper', 'css-paper', 'css-boundary-paper']):
        raise RuntimeError('Incomplete fixed native comparison')
    verify_current_admission(ROOT, observed)
    record['paper_only_admission_controls_passed'] = True
    record['complete_comparison'] = True
    path.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
