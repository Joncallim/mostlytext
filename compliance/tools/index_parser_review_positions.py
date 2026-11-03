#!/usr/bin/env python3
"""Index every parser source-unassociated position without publishing code text."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

from install_mermaid_notices import checked_map
from source_map_evidence import MappingIndex, mapped_positions, verified_bundle_map, verified_package_files
from verify_esbuild_runtime_notice import CHUNK, CHUNK_SHA, MERMAID_MAP_SHA256, MERMAID_SHA256, PARSER_SHA

ROOT = Path(__file__).resolve().parents[2]


def sha(body):
    return hashlib.sha256(body).hexdigest()


def index(root, evidence):
    reviewed = checked_map(root)
    bundle = (root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js').read_bytes()
    if sha(bundle) != MERMAID_SHA256 or sha((evidence / 'mermaid-11.17.2.tgz').read_bytes()) != reviewed['bundle']['archive_sha256']:
        raise ValueError('Pinned Mermaid input changed')
    files = verified_package_files(evidence / 'mermaid-11.17.2.tgz', json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text()))
    if sha(files['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Pinned Mermaid map changed')
    outer = verified_bundle_map(bundle, files, 'dist/mermaid.min.js')
    parser = evidence / 'parser-1.2.1.tgz'
    if sha(parser.read_bytes()) != PARSER_SHA:
        raise ValueError('Pinned parser archive changed')
    pf = verified_package_files(parser, json.loads((evidence / 'parser-1.2.1-registry.json').read_text()))
    indexes, members, hashes, runtime_ends = {}, {}, {}, {}
    for link in reviewed['parser_chunk_links']:
        name, member = link['source'], link['archive_path']
        if outer['sources'].count(name) != 1:
            raise ValueError('Ambiguous parser source')
        source = outer['sources'].index(name)
        body = outer['sourcesContent'][source].encode()
        if body != pf[member] or sha(body) != link['sha256'] or sha(pf[member + '.map']) != link['map_sha256']:
            raise ValueError('Reviewed parser chunk/map changed')
        inner = verified_bundle_map(body, pf, member)
        indexes[source], members[source], hashes[source] = MappingIndex(inner, body.decode()), member, sha(body)
        if member == CHUNK:
            if sha(body) != CHUNK_SHA:
                raise ValueError('Runtime chunk changed')
            marker = '// ../../node_modules/.pnpm/vscode-languageserver-types@3.17.5/'
            if body.decode().count(marker) != 1:
                raise ValueError('Runtime boundary changed')
            runtime_ends[source] = body[:body.index(marker.encode())].count(b'\n')
    groups = defaultdict(list)
    for generated_line, generated_column, source, line, column in mapped_positions(outer, bundle.decode()):
        if source not in indexes or indexes[source].source_at(line, column) is not None:
            continue
        groups[source, line, column].append([generated_line + 1, generated_column + 1])
    rows = []
    for (source, line, column), positions in sorted(groups.items(), key=lambda x: (members[x[0][0]], x[0][1:])):
        runtime = source in runtime_ends and line < runtime_ends[source]
        rows.append({'parser_member': members[source], 'parser_member_sha256': hashes[source],
                     'parser_line': line + 1, 'parser_utf16_column': column + 1,
                     'classification': 'credited-runtime-preamble' if runtime else 'requires-independent-review',
                     'outer_generated_positions': positions, 'outer_reference_count': len(positions)})
    total = sum(row['outer_reference_count'] for row in rows)
    credited = sum(row['outer_reference_count'] for row in rows if row['classification'] == 'credited-runtime-preamble')
    if total != reviewed['counts']['parser_points_without_inner_mapping'] or credited != 452:
        raise ValueError('Reviewed parser/runtime counts changed')
    return {'schema': 1, 'scope': 'Coordinate/hash review index; not code ownership, semantic reachability or attribution clearance',
            'mermaid_sha256': MERMAID_SHA256, 'parser_archive_sha256': PARSER_SHA,
            'coordinate_basis': 'one-based lines and UTF-16 columns',
            'original_unassociated_outer_references': total, 'credited_runtime_preamble_references': credited,
            'remaining_review_required_references': total - credited, 'positions': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = index(args.root, args.evidence_dir)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'positions'}, indent=2))


if __name__ == '__main__':
    main()
