#!/usr/bin/env python3
"""Bind candidate sysroot source files to the verified compiler-image layers."""

import argparse
import hashlib
import json
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'compliance/tools'))
import verify_viz_image as image  # noqa: E402


def sha(data):
    return hashlib.sha256(data).hexdigest()


SOURCE_SHA = 'd34ff1cb0ab99f74c0aefd4641f7a514754f2f6218d540d135ef1cf8467b08ba'


def compare(root, inputs, source_archive):
    if sha(source_archive.read_bytes()) != SOURCE_SHA:
        raise ValueError('Emscripten source archive changed')
    image.verify_installed(root, inputs)
    rows = json.loads((root / 'compliance/evidence/viz-compiler-image/layer-verification.json').read_text())
    layers = [(row['digest'], inputs / (row['digest'].removeprefix('sha256:') + '.tar.gz'))
              for row in rows]
    candidate_report = json.loads((root / 'compliance/evidence/graphviz-link-inputs/source-candidates.json').read_text())
    if candidate_report['source_archives']['emscripten']['sha256'] != SOURCE_SHA:
        raise ValueError('candidate index has a different Emscripten source')
    candidates = candidate_report['members']
    sysroot = [row for row in candidates if row['source_archive'].startswith('emscripten-')]
    if len(sysroot) != 284:
        raise ValueError('expected 284 sysroot archive members')
    wanted = {image.PREFIX + candidate['path'] for row in candidates
              if row['source_archive'].startswith('emscripten-')
              for candidate in row['basename_candidates']}
    if len(wanted) != 402:
        raise ValueError('expected 402 distinct candidate source files')
    reference = {}
    with tarfile.open(source_archive, 'r:gz') as archive:
        for member in archive:
            path = member.name.split('/', 1)[1] if '/' in member.name else ''
            key = image.PREFIX + path
            if key not in wanted:
                continue
            if not member.isfile() or key in reference or member.size > 8 * 1024 * 1024:
                raise ValueError('unsafe or duplicate selected source file')
            reference[key] = sha(archive.extractfile(member).read())
    if set(reference) != wanted:
        raise ValueError('source archive omitted candidate file')
    actual, events = image.read_selected(layers, wanted, maximum=8 * 1024 * 1024)
    if set(actual) != wanted or events:
        raise ValueError('compiler image omitted or overlaid selected source')
    comparisons = []
    for row in candidates:
        if not row['source_archive'].startswith('emscripten-'):
            continue
        for candidate in row['basename_candidates']:
            key = image.PREFIX + candidate['path']
            found = actual.get(key)
            digest = sha(found[0]) if found else None
            reference_digest = reference[key]
            if digest != reference_digest or candidate['sha256'] != reference_digest:
                raise ValueError(f'image/source/candidate mismatch: {key}')
            comparisons.append({'archive': row['archive'], 'member': row['member'],
                                'source_path': candidate['path'],
                                'reference_sha256': reference_digest,
                                'candidate_sha256': candidate['sha256'],
                                'image_sha256': digest,
                                'image_layer': found[1] if found else None,
                                'equal': True})
    if len(comparisons) != 402:
        raise ValueError('candidate comparison count changed')
    return {'schema': 1, 'image_index_sha256': image.INDEX_SHA,
            'source_reference': '263db4cffa6f9fc2ec514a70abac81362ea41849',
            'source_archive_sha256': SOURCE_SHA,
            'requested_paths': len(wanted), 'found_paths': len(actual),
            'overlay_events': events, 'candidate_comparisons': comparisons}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--emscripten-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(compare(ROOT, args.inputs, args.emscripten_source), indent=2) + '\n')
