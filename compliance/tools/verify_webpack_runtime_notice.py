#!/usr/bin/env python3
"""Check a qualified MIT reference for four retained Webpack runtime bodies."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from audit_cytoscape_attribution import MERMAID_SHA256, MERMAID_MAP_SHA256
from source_map_evidence import MappingIndex, mapped_positions, verified_bundle_map, verified_package_files

ROOT = Path(__file__).resolve().parents[2]
ID = 'webpack-parser-runtime'
PACKET = 'compliance/evidence/webpack-parser-runtime'
REFERENCE_SHA = '7432a589823b59cd6eb501ba96315a99476628ca21f30992d59b099449c728a6'
LICENSE_PATH = 'compliance/licenses/webpack-parser-runtime--MIT.txt'
LICENSE_SHA = '9068a8782d2fb4c6e432cfa25334efa56f722822180570802bf86e71b6003b1e'
MAPPING_SHA = '64e37346adfe1cd5f98626851ea1b4bfc580937529205b9ff7111dbf32e57193'
BUILD_MANIFEST_SHA = 'd5b981f5ef9159d6282498ff855783282148b72711b3bcf03d741e554965dded'
PARSER_SHA = '97eef1a4c37110e4836b6eb8dd6a348d989efb370a7672831df01042a7c323f4'
CHUNK = 'dist/chunks/mermaid-parser.core/chunk-FOHPRMQF.mjs'
CHUNK_SHA = '5c83305b04a62463567bdf6d82d9ba9dfc3795e516d8cc848e6981504af48068'
REGIONS = [
    ('bootstrap', 'bootstrap', '4158dea042576a3385c74915858d23ff819d6e19839c43832e741eeee77638d6', 'return module.exports;'),
    ('define%20property%20getters', 'runtime/define property getters', '8887a7a4ae920342bb9109b1d8e4a7deddf67d2bb59309fe935121acf0d65d6d', 'Object.defineProperty(exports, key,'),
    ('hasOwnProperty%20shorthand', 'runtime/hasOwnProperty shorthand', '2fc045876ffafa261598b1d1476ffb16010e9fed737aa98bd4545e5fb2867777', 'Object.prototype.hasOwnProperty.call'),
    ('make%20namespace%20object', 'runtime/make namespace object', 'dcb6fa6d79b08ff7453817108c79154a90678e58f0ba43820f694a7311f22fd8', "Object.defineProperty(exports, '__esModule'"),
]


def sha(body):
    return hashlib.sha256(body).hexdigest()


def match_complete(generated, reference):
    if generated != reference:
        raise ValueError('Complete Webpack source content differs; no normalization is admitted')


def component():
    return {'id': ID, 'name': 'Webpack parser runtime helpers (matching licensed reference; emitting version unresolved)',
            'kind': 'attribution', 'version': 'emitting version unresolved; reference 5.88.2',
            'upstream': 'https://github.com/webpack/webpack', 'licence': 'MIT',
            'copyright': ['Copyright JS Foundation and other contributors'],
            'licence_texts': [{'path': LICENSE_PATH, 'sha256': LICENSE_SHA,
                              'upstream': 'https://registry.npmjs.org/webpack/-/webpack-5.88.2.tgz',
                              'upstream_archive_sha256': '4d92a947dbc855289a1a33a9a77dd9a2cf04606d721a74b18104de29aa1f8279',
                              'upstream_revision': '1f99ad6367f2b8a6ef17cce0e058f7a67fb7db18', 'upstream_path': 'package/LICENSE'}],
            'provenance': 'verified', 'resolution': 'matching-runtime-reference; original emitting version unresolved',
            'lc': ['LC-01', 'LC-07'], 'evidence': PACKET + '/mapping.json',
            'notes': 'Four complete retained runtime source bodies match a generated Webpack 5.88.2 reference byte-for-byte without normalization, with actual composed body-operation probes. This does not identify the earlier emitting Webpack version, imply whole compiler package inclusion or complete nested attribution.'}


def reference_bodies(raw):
    if sha(raw) != REFERENCE_SHA:
        raise ValueError('Generated licensed Webpack reference map changed')
    data = json.loads(raw)
    result = {}
    for target, reference, digest, probe in REGIONS:
        name = 'webpack://Fixture/webpack/' + reference
        if data['sources'].count(name) != 1:
            raise ValueError('Missing/ambiguous complete Webpack reference')
        body = data['sourcesContent'][data['sources'].index(name)]
        if sha(body.encode()) != digest or body.count(probe) != 1:
            raise ValueError('Licensed Webpack reference body/probe changed')
        result[target] = body
    return result


def validate_mapping(data):
    if (data.get('shipped_bundle_sha256') != MERMAID_SHA256
            or data.get('parser_archive_sha256') != PARSER_SHA
            or data.get('reference_map_sha256') != REFERENCE_SHA
            or data.get('license_sha256') != LICENSE_SHA
            or data.get('reference_version') != '5.88.2'
            or data.get('original_emitter_version') != 'unresolved'):
        raise ValueError('Webpack mapped-input binding changed')
    rows = data.get('helpers', [])
    expected = {name: digest for name, _, digest, _ in REGIONS}
    if len(rows) != 4 or {row.get('helper') for row in rows} != set(expected):
        raise ValueError('Complete four-helper reference required')
    for row in rows:
        if row.get('body_sha256') != expected[row['helper']]:
            raise ValueError('Webpack full source body changed')
        refs, probes = row.get('generated_references'), row.get('generated_body_probe_references')
        if type(refs) is not int or type(probes) is not int or not 0 < probes <= refs:
            raise ValueError('Actual mapped Webpack body operation required')


    if (sum(row['generated_references'] for row in rows) != data.get('mapped_runtime_references')
            or data['mapped_runtime_references'] != 125
            or sum(row['generated_body_probe_references'] for row in rows) != 42):
        raise ValueError('Complete reviewed Webpack reference counts changed')


def verify_installed(root=ROOT):
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    if [row for row in inventory['components'] if row['id'] == ID] != [component()]:
        raise ValueError('Qualified Webpack runtime attribution changed')
    if sha((root / LICENSE_PATH).read_bytes()) != LICENSE_SHA:
        raise ValueError('Distributed Webpack MIT text changed')
    shipped = root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js'
    if sha(shipped.read_bytes()) != MERMAID_SHA256:
        raise ValueError('Current shipped Mermaid differs from Webpack mapping')
    raw = (root / PACKET / 'mapping.json').read_bytes()
    if sha(raw) != MAPPING_SHA:
        raise ValueError('Pinned Webpack runtime mapping changed')
    validate_mapping(json.loads(raw))
    reference_bodies((root / PACKET / 'reference-map.json').read_bytes())
    raw_build = (root / PACKET / 'reference-build-manifest.json').read_bytes()
    if sha(raw_build) != BUILD_MANIFEST_SHA:
        raise ValueError('Pinned reference-build recipe changed')
    for name, digest in json.loads(raw_build)['files'].items():
        if '/' in name or name in ('.', '..') or sha((root / PACKET / name).read_bytes()) != digest:
            raise ValueError('Pinned reference-build input changed: ' + name)


def replay(root, evidence, reference):
    bodies = reference_bodies(reference.read_bytes())
    files = verified_package_files(evidence / 'mermaid-11.17.2.tgz',
                                  json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text()))
    bundle = (root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js').read_bytes()
    if sha(bundle) != MERMAID_SHA256 or sha(files['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Pinned shipped Mermaid/map changed')
    outer = verified_bundle_map(bundle, files, 'dist/mermaid.min.js')
    parser = evidence / 'parser-1.2.1.tgz'
    if sha(parser.read_bytes()) != PARSER_SHA:
        raise ValueError('Pinned parser archive changed')
    pf = verified_package_files(parser, json.loads((evidence / 'parser-1.2.1-registry.json').read_text()))
    source = '../../parser/' + CHUNK
    if outer['sources'].count(source) != 1 or sha(pf[CHUNK]) != CHUNK_SHA:
        raise ValueError('Parser chunk identity changed')
    index = outer['sources'].index(source)
    chunk = outer['sourcesContent'][index]
    if chunk.encode() != pf[CHUNK]:
        raise ValueError('Outer mapped parser bytes changed')
    inner = verified_bundle_map(chunk.encode(), pf, CHUNK)
    lookup = MappingIndex(inner, chunk)
    selected, rows = {}, []
    for name, _, digest, probe in REGIONS:
        target = 'webpack://LIB/webpack/' + (name if name == 'bootstrap' else 'runtime/' + name)
        if inner['sources'].count(target) != 1:
            raise ValueError('Missing/ambiguous retained Webpack source')
        si = inner['sources'].index(target)
        body = inner['sourcesContent'][si]
        match_complete(body, bodies[name])
        line = body.count('\n', 0, body.index(probe))
        selected[si] = (name, line)
        rows.append({'helper': name, 'source': target, 'body_sha256': digest, 'probe_line': line + 1})
    refs, probes = Counter(), Counter()
    for _, _, origin, line, column in mapped_positions(outer, bundle.decode()):
        if origin != index:
            continue
        linked = lookup.source_at(line, column)
        if linked is None or linked[0] not in selected:
            continue
        name, probe = selected[linked[0]]
        refs[name] += 1
        if linked[1] == probe:
            probes[name] += 1
    for row in rows:
        row.update(generated_references=refs[row['helper']], generated_body_probe_references=probes[row['helper']])
    result = {'schema': 1, 'id': ID, 'shipped_bundle_sha256': MERMAID_SHA256,
              'parser_archive_sha256': PARSER_SHA, 'parser_chunk_sha256': CHUNK_SHA,
              'reference_map_sha256': REFERENCE_SHA, 'reference_version': '5.88.2',
              'original_emitter_version': 'unresolved', 'license_sha256': LICENSE_SHA,
              'mapped_runtime_references': sum(refs.values()), 'helpers': rows}
    validate_mapping(result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--evidence-dir', type=Path)
    parser.add_argument('--reference-map', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if any([args.evidence_dir, args.reference_map, args.output]):
        if not all([args.evidence_dir, args.reference_map, args.output]):
            parser.error('Replay requires evidence-dir, reference-map and output')
        result = replay(args.root, args.evidence_dir, args.reference_map)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps(result, indent=2))
    else:
        verify_installed(args.root)
        print('Qualified Webpack runtime MIT notice: passed')
