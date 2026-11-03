#!/usr/bin/env python3
"""Verify a qualified MIT notice for emitted parser runtime helpers."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from audit_cytoscape_attribution import MERMAID_MAP_SHA256, MERMAID_SHA256
from install_mermaid_notices import checked_map
from source_map_evidence import MappingIndex, mapped_positions, verified_bundle_map, verified_package_files

ROOT = Path(__file__).resolve().parents[2]
REFERENCE_SHA = 'a23de38cb7e78582039ad707b4625dd1f298f15fa000d6f52f6eb6cb08e1e79b'
LICENSE_SHA = 'b40ec5baec7bb34fa5b1c09521fa3cd52d5fad7adafed74932a2010d3612a681'
PARSER_SHA = '97eef1a4c37110e4836b6eb8dd6a348d989efb370a7672831df01042a7c323f4'
CHUNK = 'dist/chunks/mermaid-parser.core/chunk-FOHPRMQF.mjs'
CHUNK_SHA = '5c83305b04a62463567bdf6d82d9ba9dfc3795e516d8cc848e6981504af48068'
LICENSE_PATH = 'compliance/licenses/esbuild-parser-runtime--MIT.txt'
ID = 'esbuild-parser-runtime'
REGIONS = [
    ('commonjs', 'var __commonJS =', 'var __export =', 'export var __commonJS =',
     'export var __commonJSMin =', '  return mod ||'),
    ('exports', 'var __export =', 'var __copyProps =', 'export var __export =',
     'var __copyProps =', '  for (var name in all)')]


def sha(body):
    return hashlib.sha256(body).hexdigest()


def select(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('Missing or ambiguous helper boundary')
    a, b = source.index(start), source.index(end)
    if a >= b:
        raise ValueError('Helper boundary order changed')
    return source[a:b], source.count('\n', 0, a), source.count('\n', 0, b)


def helper_tokens(source):
    """Formatting comparison only for the two pinned, string/regex-free bodies.

    Not a general JavaScript lexer or semantic-equivalence test. Complete raw
    inputs are separately pinned and the exact compared bodies remain hashed.
    """
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    if any(char in source for char in '\'"`\\/') or re.search(r'\breturn[^\S\r\n]*[\r\n]', source):
        raise ValueError('String, regex, escape or return-line break outside reviewed helper subset')
    tokens = re.findall(r'[A-Za-z_$][A-Za-z0-9_$]*|\d+|===|!==|=>|\|\||&&|==|!=|[^\s;]', source)
    if tokens[:1] == ['export']:
        tokens = tokens[1:]
    return tokens


def match_helper(generated, reference):
    if helper_tokens(generated) != helper_tokens(reference):
        raise ValueError('Complete helper token correspondence changed')


def component():
    return {'id': ID, 'name': 'esbuild parser runtime helpers (matching licensed reference; emitting version unresolved)',
            'kind': 'attribution', 'version': 'emitting version unresolved; reference v0.27.7',
            'upstream': 'https://github.com/evanw/esbuild', 'licence': 'MIT',
            'copyright': ['Copyright (c) 2020 Evan Wallace'],
            'licence_texts': [{'path': LICENSE_PATH, 'sha256': LICENSE_SHA,
                'upstream': 'https://github.com/evanw/esbuild',
                'upstream_revision': '2025c9ff6ab15ba6b0f9d074fd732250cc46e4a3', 'upstream_path': 'LICENSE.md'}],
            'provenance': 'verified', 'resolution': 'matching-runtime-reference; original emitting version unresolved',
            'lc': ['LC-01', 'LC-07'], 'evidence': 'compliance/evidence/esbuild-parser-runtime/mapping.json',
            'notes': 'Two complete emitted helper bodies match the licensed reference after narrowly reviewed formatting normalization. No exact npm identity, original compiler-version proof, full runtime reachability or complete nested audit is claimed.'}


def verify_installed(root):
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    if [c for c in inventory['components'] if c['id'] == ID] != [component()]:
        raise ValueError('Qualified runtime attribution changed')
    if sha((root / LICENSE_PATH).read_bytes()) != LICENSE_SHA:
        raise ValueError('Distributed runtime MIT text changed')


def replay(root, evidence, reference):
    verify_installed(root)
    raw = reference.read_bytes()
    if sha(raw) != REFERENCE_SHA:
        raise ValueError('Licensed runtime source changed')
    files = verified_package_files(evidence / 'mermaid-11.17.2.tgz',
                                  json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text()))
    bundle = (root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js').read_bytes()
    if sha(bundle) != MERMAID_SHA256 or sha(files['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Pinned shipped bundle/map changed')
    outer = verified_bundle_map(bundle, files, 'dist/mermaid.min.js')
    parser = evidence / 'parser-1.2.1.tgz'
    if sha(parser.read_bytes()) != PARSER_SHA:
        raise ValueError('Pinned parser archive changed')
    pf = verified_package_files(parser, json.loads((evidence / 'parser-1.2.1-registry.json').read_text()))
    source_name = '../../parser/' + CHUNK
    if outer['sources'].count(source_name) != 1 or sha(pf[CHUNK]) != CHUNK_SHA:
        raise ValueError('Parser chunk identity changed')
    index = outer['sources'].index(source_name)
    chunk = outer['sourcesContent'][index]
    if chunk.encode() != pf[CHUNK]:
        raise ValueError('Mapped runtime chunk differs from official parser')
    inner = MappingIndex(verified_bundle_map(chunk.encode(), pf, CHUNK), chunk)
    spans, rows = {}, []
    for name, start, end, ref_start, ref_end, probe in REGIONS:
        body, first, stop = select(chunk, start, end)
        ref, _, _ = select(raw.decode(), ref_start, ref_end)
        match_helper(body, ref)
        if body.count(probe) != 1:
            raise ValueError('Missing or ambiguous runtime body probe')
        line = first + body.count('\n', 0, body.index(probe))
        spans[name] = (first, stop, line)
        rows.append({'helper': name, 'source_first_line': first + 1, 'source_end_line_exclusive': stop + 1,
                     'body_sha256': sha(body.encode()), 'reference_body_sha256': sha(ref.encode()),
                     'normalized_token_sha256': sha(json.dumps(helper_tokens(body)).encode())})
    marker = '// ../../node_modules/.pnpm/vscode-languageserver-types@3.17.5/'
    if chunk.count(marker) != 1:
        raise ValueError('Runtime preamble boundary changed')
    end_line = chunk.count('\n', 0, chunk.index(marker))
    total, refs, probes = 0, Counter(), Counter()
    for _, _, origin, line, column in mapped_positions(outer, bundle.decode()):
        if origin != index:
            continue
        if line < end_line:
            if inner.source_at(line, column) is not None:
                raise ValueError('Expected runtime preamble classification changed')
            total += 1
        for name, (first, stop, probe_line) in spans.items():
            if first <= line < stop:
                refs[name] += 1
            if line == probe_line:
                probes[name] += 1
    for row in rows:
        name = row['helper']
        if not refs[name] or not probes[name]:
            raise ValueError('Actual mapped helper body code required')
        row.update(generated_references=refs[name], generated_body_probe_references=probes[name])
    original = checked_map(root)['counts']['parser_points_without_inner_mapping']
    if not 0 < total <= original:
        raise ValueError('Unexpected runtime preamble count')
    return {'schema': 1, 'id': ID, 'shipped_bundle_sha256': MERMAID_SHA256, 'parser_archive_sha256': PARSER_SHA,
            'parser_chunk_sha256': CHUNK_SHA, 'reference_source_sha256': REFERENCE_SHA,
            'reference_revision': '2025c9ff6ab15ba6b0f9d074fd732250cc46e4a3', 'license_sha256': LICENSE_SHA,
            'helpers': rows, 'classified_runtime_preamble_references': total,
            'original_unassociated_parser_positions': original,
            'remaining_unassociated_positions_not_classified_here': original - total,
            'emitting_version_proved': False, 'complete_embedded_attribution': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--evidence-dir', type=Path)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if any([args.evidence_dir, args.reference, args.output]):
        if not all([args.evidence_dir, args.reference, args.output]):
            parser.error('full replay needs evidence-dir, reference and output')
        result = replay(args.root, args.evidence_dir, args.reference)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps(result, indent=2))
    else:
        verify_installed(args.root)
        print('Qualified parser runtime MIT notice: passed')


if __name__ == '__main__':
    main()
