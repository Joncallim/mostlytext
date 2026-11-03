#!/usr/bin/env python3
"""Verify two emitted Cytoscape helper attributions without executing packages."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from source_map_evidence import mapped_positions, verified_bundle_map, verified_package_files

MERMAID_SHA256 = '581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8'
MERMAID_MAP_SHA256 = '43cd977e8e0f351d6c47d31302c564f1c21fdc1e0be0d9e46370ee5e23cea004'
CYTOSCAPE_LICENCE_SHA256 = 'eb319c6e6f233607f71e8e2f450391751883cfc0eeb3ca7ef574c13d1d9c2203'
CYTOSCAPE_SHA256 = '9ffbc8172ca3bd6723fba3513f96194f0e4c98225e00f380948f285869517803'
SOURCE_NAME = '../../../node_modules/.pnpm/cytoscape@3.34.0/node_modules/cytoscape/dist/cytoscape.esm.mjs'
ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'compliance/evidence/cytoscape-borrowed-attribution/references.json'


def digest(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def checked_file(path: Path, expected: str) -> bytes:
    body = path.read_bytes()
    if digest(body) != expected:
        raise ValueError('Evidence digest changed: ' + path.name)
    return body


def fragment(source: str, start: str, end: str, credit: str, probes: list[str]) -> dict:
    """Select a unique credited code region, with zero-based map line bounds."""
    if source.count(start) != 1 or source.count(end) != 1 or source.count(credit) != 1:
        raise ValueError('Missing or ambiguous fragment/credit boundary')
    begin, stop, header = source.index(start), source.index(end), source.index(credit)
    if not header < begin < stop:
        raise ValueError('Credit and fragment boundaries are out of order')
    # End marker occupies its own later line. Neither marker nor preceding
    # credit comments count as evidence that the fragment's code was emitted.
    if (begin and source[begin - 1] != '\n') or (stop and source[stop - 1] != '\n'):
        raise ValueError('Fragment boundaries must begin source lines')
    probe_lines = []
    for probe in probes:
        if source.count(probe) != 1 or not begin <= source.index(probe) < stop:
            raise ValueError('Missing or ambiguous code probe within fragment')
        probe_lines.append(source.count('\n', 0, source.index(probe)))
    if not probe_lines:
        raise ValueError('Credited fragments require specific code probes')
    return {'probe_lines': probe_lines, 'first_line': source.count('\n', 0, begin),
            'end_line_exclusive': source.count('\n', 0, stop),
            'source_sha256': digest(source[begin:stop].encode()),
            'credit_sha256': digest(credit.encode())}


def fragment_references(positions, source_index: int, ranges: dict) -> dict:
    counts = Counter()
    lines = {key: set() for key in ranges}
    probe_counts = {key: Counter() for key in ranges}
    for _, _, index, line, _ in positions:
        if index != source_index:
            continue
        for key, span in ranges.items():
            if span['first_line'] <= line < span['end_line_exclusive']:
                counts[key] += 1
                lines[key].add(line)
                if line in span['probe_lines']:
                    probe_counts[key][line] += 1
    if any(not counts[key] for key in ranges):
        raise ValueError('Every credited fragment requires mapped generated code')
    if any(not probe_counts[key][line] for key, span in ranges.items() for line in span['probe_lines']):
        raise ValueError('Every specific borrowed-code probe must map to generated code')
    return {key: {'generated_references': counts[key], 'mapped_source_lines': len(lines[key]),
                  'generated_probe_references': [{'source_line': line + 1, 'references': probe_counts[key][line]} for line in ranges[key]['probe_lines']]}
            for key in sorted(ranges)}


def audit(evidence: Path, references: Path, shipped: Path, licence_dir: Path) -> dict:
    meta = json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text())
    if (meta.get('name'), meta.get('version')) != ('mermaid', '11.17.2'):
        raise ValueError('Unexpected Mermaid identity')
    package = verified_package_files(evidence / 'mermaid-11.17.2.tgz', meta)
    bundle = checked_file(shipped, MERMAID_SHA256)
    if digest(package['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Official source-map digest changed')
    outer = verified_bundle_map(bundle, package, 'dist/mermaid.min.js')
    cyto = evidence / 'npm-packages/cytoscape@3.34.0'
    meta = json.loads((cyto / 'registry.json').read_text())
    if (meta.get('name'), meta.get('version')) != ('cytoscape', '3.34.0'):
        raise ValueError('Unexpected Cytoscape identity')
    files = verified_package_files(cyto / 'package.tgz', meta)
    source = files['dist/cytoscape.esm.mjs']
    if digest(source) != CYTOSCAPE_SHA256 or outer['sources'].count(SOURCE_NAME) != 1:
        raise ValueError('Unexpected Cytoscape mapped source identity')
    index = outer['sources'].index(SOURCE_NAME)
    if outer['sourcesContent'][index].encode() != source:
        raise ValueError('Mapped Cytoscape differs from exact official archive member')
    spec = json.loads(SPEC.read_text())
    ids = [item['id'] for item in spec['attributions']]
    if spec.get('schema') != 1 or sorted(ids) != ['cytoscape-bezier-easing', 'cytoscape-jquery-events']:
        raise ValueError('Both distinct reviewed attributions are required')
    if digest(files['LICENSE']) != CYTOSCAPE_LICENCE_SHA256:
        raise ValueError('Official Cytoscape license digest changed')
    if (licence_dir / 'cytoscape--MIT.txt').read_bytes() != files['LICENSE']:
        raise ValueError('Distributed Cytoscape license differs from official archive')
    ranges = {item['id']: fragment(source.decode(), item['start'], item['end'], item['credit'], item['probes'])
              for item in spec['attributions']}
    counts = fragment_references(mapped_positions(outer, bundle.decode()), index, ranges)
    result = []
    for item in spec['attributions']:
        reference = item['reference']
        ref_source = checked_file(references / reference['source_file'], reference['source_sha256'])
        ref_license = checked_file(references / reference['licence_file'], reference['licence_sha256'])
        if (licence_dir / item['distributed_licence']).read_bytes() != ref_license:
            raise ValueError('Distributed license differs from official reference: ' + item['id'])
        if any(marker.encode() not in ref_source for marker in reference['source_markers']):
            raise ValueError('Reference does not contain the matching credited helper')
        result.append({'id': item['id'],
                       'first_source_line': ranges[item['id']]['first_line'] + 1,
                       'end_source_line_exclusive': ranges[item['id']]['end_line_exclusive'] + 1,
                       'fragment_sha256': ranges[item['id']]['source_sha256'],
                       'credit_sha256': ranges[item['id']]['credit_sha256'], **counts[item['id']],
                       'reference_repository': reference['repository'],
                       'reference_revision': reference['revision'],
                       'reference_source_sha256': digest(ref_source),
                       'distributed_licence': item['distributed_licence'],
                       'licence_sha256': digest(ref_license),
                       'adaptation_limit': 'Matching licensed reference; Cytoscape does not identify the original adaptation revision'})
    return {'schema': 1, 'scope': 'Two conservative helper attributions, not complete Mermaid/Cytoscape notice closure or legal clearance',
            'shipped_mermaid_sha256': digest(bundle),
            'mermaid_archive_sha256': digest((evidence / 'mermaid-11.17.2.tgz').read_bytes()),
            'mermaid_map_sha256': digest(package['dist/mermaid.min.js.map']),
            'cytoscape_archive_sha256': digest((cyto / 'package.tgz').read_bytes()),
            'cytoscape_mapped_source_sha256': digest(source),
            'cytoscape_licence_sha256': digest(files['LICENSE']),
            'attributions': result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--reference-dir', type=Path, required=True)
    parser.add_argument('--shipped', type=Path, required=True)
    parser.add_argument('--licence-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.evidence_dir, args.reference_dir, args.shipped, args.licence_dir)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({item['id']: item['generated_references'] for item in report['attributions']}))


if __name__ == '__main__':
    main()
