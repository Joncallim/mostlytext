#!/usr/bin/env python3
"""Recognize only the fixed ordinary-export canary's actual PDFSelection row."""
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path('/Users/runner/work/_temp/mostlytext-focus')
ORIGINAL_PACKET = Path('planning/downstream/evidence/ordinary-export-pdf-original-failure-2026-11-08')
CORRECTED_PACKET = Path('planning/downstream/evidence/paper-canvas-qualified-firsts-2026-11-08')
EXPECTED = 'NATIVE_EXPORT_CANARY'
PDFS = {
    'original': ('ce2b5cc91a8a774c894c43d0f1fe56d4f95cce32171a80c8c2b0f70785af0ae6', 16424),
    'corrected': ('d95a9e149c236e572551cc6cc913bc044d80822c8a14796a438ce6f5171aab08', 15107),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def decoded_record(packet, row):
    name = row['file']
    if Path(name).name != name or not name.endswith('.gz') or type(row['bytes']) is not int or not 0 < row['bytes'] < 4 * 1024 * 1024:
        raise ValueError('Unbounded or redirected evidence record')
    path = packet / name
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('Evidence must be a bounded regular source file')
    with gzip.open(path, 'rb') as stream:
        raw = stream.read(row['bytes'] + 1)
    if len(raw) != row['bytes'] or sha(raw) != row['sha256']:
        raise ValueError('Evidence bytes differ from their original record')
    return raw


def rectangle(value):
    if not isinstance(value, list) or len(value) != 4 or any(type(n) not in (int, float) or not math.isfinite(n) for n in value):
        raise ValueError('Invalid selection rectangle')
    if value[2] <= 0 or value[3] <= 0:
        raise ValueError('Empty selection rectangle')
    return value


def placed_heading(page):
    media = rectangle(page['media_box'])
    raw = page['raw_page_text']
    if not isinstance(raw, str) or len(raw.encode('utf-16-le')) // 2 != page['character_count'] or not 0 < page['character_count'] <= 16384:
        raise ValueError('Invalid bounded raw text')
    units = raw.encode('utf-16-le')
    rows = page['character_geometry']
    if not isinstance(rows, list) or len(rows) != page['character_count']:
        raise ValueError('Missing character records')
    glyphs = []
    for index, row in enumerate(rows):
        char = units[2 * index:2 * index + 2].decode('utf-16-le', errors='surrogatepass')
        if type(row['utf16_index']) is not int or row['utf16_index'] != index or row['raw_index_text'] != char:
            raise ValueError('Changed, duplicated or reordered UTF-16 indices')
        if char.isspace():
            continue  # PDFKit newline selections can duplicate the preceding glyph.
        if not row['selection_present'] or row['selection_text'] != char or row['selection_geometry_state'] != 'rect':
            raise ValueError('Actual selection differs from its raw character')
        x, y, w, h = rectangle(row['selection_bounds'])
        if x < media[0] or y < media[1] or x + w > media[0] + media[2] or y + h > media[1] + media[3]:
            raise ValueError('Character selection lies outside the page')
        glyphs.append((char, x, y, w, h))
    if not glyphs:
        raise ValueError('No actual glyphs')
    height = max(g[4] for g in glyphs)
    heading = [g for g in glyphs if abs(g[4] - height) <= 0.01]
    if len(heading) != len(EXPECTED):
        raise ValueError('The uniquely largest row must contain exactly twenty characters')
    heading.sort(key=lambda g: g[1])
    y = heading[0][2]
    if any(abs(g[2] - y) > 0.01 or g[0] not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_' for g in heading):
        raise ValueError('Heading glyphs do not share one ASCII row')
    for left, right in zip(heading, heading[1:]):
        if not (right[1] > left[1] and right[1] + right[3] / 2 > left[1] + left[3] / 2 and abs(right[1] - left[1] - left[3]) <= height * 0.1):
            raise ValueError('Collapsed or separated heading glyph positions')
    text = ''.join(g[0] for g in heading)
    if text != EXPECTED:
        raise ValueError('Visible heading order is not the exact canary')
    return {'ordered_heading': text, 'characters': len(heading), 'row_height': height, 'row_y': y}


def evaluate(result):
    pages = result['pages']
    if not isinstance(pages, list) or not 1 <= len(pages) <= 10:
        raise ValueError('Invalid page count')
    heading = placed_heading(pages[0])
    return {**heading, 'page_count': len(pages), 'short_fixture_accepted': len(pages) == 1}


def inputs():
    old = json.loads((ORIGINAL_PACKET / 'manifest.json').read_bytes())
    new = json.loads((CORRECTED_PACKET / 'manifest.json').read_bytes())
    if old['source'] != '734db2f2cd083c040365919134163b55ed57f41f' or old['native_run'] != 42424848502 or old['whole_result'] != 'failure':
        raise ValueError('Original failed first changed')
    if new['source'] != 'fd23e3e264e9f34dd093151bb0f5474b0466f8c7' or new['all_seven_complete_firsts'] != 'PASS':
        raise ValueError('Corrected qualified source changed')
    rows = {
        'original': (ORIGINAL_PACKET, [r for r in old['records'] if r['original_name'] == 'ordinary-export.pdf']),
        'corrected': (CORRECTED_PACKET, [r for r in new['records'] if r['original_path'] == 'native_canvas-first-artifact/native-pdf-snapshot-frames/css-paper-paginated.pdf']),
    }
    out = {}
    for name, (packet, records) in rows.items():
        if len(records) != 1:
            raise ValueError('Missing or duplicate fixed PDF')
        raw = decoded_record(packet, records[0])
        if (sha(raw), len(raw)) != PDFS[name]:
            raise ValueError('Substitute PDF bytes')
        out[name] = raw
    return out


def main():
    if sys.flags.optimize or sys.argv[1:] not in [['prepare'], ['observe']]:
        raise ValueError('Select fixed nonoptimized phase')
    spec = importlib.util.spec_from_file_location('host_guard', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    guard.check_host(ROOT)
    pdfs = inputs()
    names = ['.github/scripts/verify-placed-pdf-canary.py', '.github/scripts/test-placed-pdf-canary.py',
             '.github/scripts/prepare-hosted-public-focus.py', '.github/fixtures/original-canary-selections.json.gz',
             '.github/hosted-export-acceptance/ReadPlacedPDF.swift',
             '.github/workflows/placed-pdf-canary.yml', str(ORIGINAL_PACKET / 'manifest.json'), str(CORRECTED_PACKET / 'manifest.json')]
    sources = {p: sha(Path(p).read_bytes()) for p in names}
    path = ROOT / 'placed-pdf-receipt.json'
    if sys.argv[1] == 'prepare':
        if ROOT.exists() or ROOT.is_symlink():
            raise ValueError('Fixed root must be fresh')
        ROOT.mkdir(mode=0o700)
        for name, raw in pdfs.items():
            (ROOT / (name + '.pdf')).write_bytes(raw)
        record = {'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), 'source_sha256': sources,
                  'pdfs': {n: {'sha256': sha(b), 'bytes': len(b)} for n, b in pdfs.items()}, 'app_GUI_launches': 0,
                  'host': {'uid': os.getuid(), 'os': subprocess.check_output(['sw_vers'], text=True),
                           'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True)},
                  'scope': 'Retained fixed-output oracle qualification only; no ordinary-menu or exact-RC acceptance'}
        path.write_text(json.dumps(record, indent=2) + '\n')
        return
    record = json.loads(path.read_bytes())
    if record['source_sha256'] != sources or record['checkout'] != subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip():
        raise ValueError('Source changed after admission')
    for name, raw in pdfs.items():
        if (ROOT / (name + '.pdf')).read_bytes() != raw:
            raise ValueError('Admitted PDF changed')
    record['compiled_sha256'] = sha((ROOT / 'read-placed-pdf').read_bytes())
    path.write_text(json.dumps(record, indent=2) + '\n')
    with (ROOT / 'native.stdout').open('wb') as stdout, (ROOT / 'native.stderr').open('wb') as stderr:
        run = subprocess.run([str(ROOT / 'read-placed-pdf')], stdout=stdout, stderr=stderr, timeout=30)
    record['native_returncode'] = run.returncode
    path.write_text(json.dumps(record, indent=2) + '\n')
    if run.returncode:
        raise ValueError('Actual native selection readback failed')
    record['actual_evaluations'] = {}
    for name in pdfs:
        observed = json.loads((ROOT / (name + '-selection.json')).read_bytes())
        if observed['sha256'] != PDFS[name][0] or observed['bytes'] != PDFS[name][1]:
            raise ValueError('Native input identity differs')
        result = evaluate(observed)
        record['actual_evaluations'][name] = result
        path.write_text(json.dumps(record, indent=2) + '\n')
        if result['page_count'] != (2 if name == 'original' else 1) or result['short_fixture_accepted'] != (name == 'corrected'):
            raise ValueError('Original must refuse and corrected short PDF must pass')
    record['qualified_fixed_oracle'] = True
    path.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
