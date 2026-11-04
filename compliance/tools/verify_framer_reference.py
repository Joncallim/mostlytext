#!/usr/bin/env python3
"""Verify a matching Framer MIT source reference without claiming original input."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from audit_cytoscape_attribution import (CYTOSCAPE_SHA256, MERMAID_MAP_SHA256,
    MERMAID_SHA256, SOURCE_NAME, fragment, fragment_references)
from source_map_evidence import mapped_positions, verified_bundle_map, verified_package_files

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/framer-mit-reference'
SPEC_SHA = '0b2c5699b8f138e41994b0c5d9604511921596c392edf4e24e5ccf2377a27064'
NOTICE = 'compliance/licenses/cytoscape-framer-spring--MIT.txt'
NOTICE_SHA = '298012b8b6c965d489221b5b79be5f77ca2027ec65d47a80b16b73812cb60a46'
REVISION = 'a41d843dc1371dd0cdc87d1fbbb3f833a5d24d58'
ID = 'cytoscape-framer-spring'
MAPPING_SHA = '683119f8d539f4640c41126db315a0a0a6cbff095b5e12b35765b1c8edc61159'
START = 'var generateSpringRK4 = function () {'
END = 'var cubicBezier = function cubicBezier('
CREDIT = '/*! Runge-Kutta spring physics function generator. Adapted from Framer.js, copyright Koen Bok. MIT License: http://en.wikipedia.org/wiki/MIT_License */'
PROBES = ['  function springAccelerationForState(state) {',
          '  function springEvaluateStateWithDerivative(initialState, dt, derivative) {',
          '  function springIntegrateState(state, dt) {',
          '  return function springRK4Factory(tension, friction, duration) {']


def sha(body):
    return hashlib.sha256(body).hexdigest()


def component():
    return {'id': ID, 'name': 'Koen Bok Framer spring helper (via Cytoscape/Mermaid)',
            'kind': 'attribution', 'version': 'Matching Framer 3.0.0 MIT reference; original adaptation unspecified',
            'upstream': 'https://github.com/koenbok/Framer', 'licence': 'MIT',
            'copyright': ['Copyright (c) 2014 Koen Bok'],
            'licence_texts': [{'path': NOTICE, 'sha256': NOTICE_SHA,
                'upstream': 'https://github.com/koenbok/Framer', 'upstream_revision': REVISION,
                'upstream_path': 'LICENSE'}], 'provenance': 'verified',
            'resolution': 'matching licensed reference; original adaptation revision unspecified',
            'lc': ['LC-01', 'LC-07'], 'evidence': PACKET + '/mapping.json',
            'notes': 'Conservative matching-source attribution for the Framer/Koen spring helper expressly credited under MIT by Cytoscape. The actual 2014 MIT reference contains the same four-helper CoffeeScript block as the older BSD-style comparison. Four specific spring probes map into shipped Mermaid. Wrapping/inlining/parameter adaptations remain explicit; this is not a unique original-input, complete compiled-body equality or independent rights determination. Older BSD/intermediary evidence and Mermaid review-required items remain open.'}


def specification(root):
    body = (root / PACKET / 'reference.json').read_bytes()
    if sha(body) != SPEC_SHA:
        raise ValueError('Pinned Framer source reference changed')
    return json.loads(body)


def helper_block(source):
    start = 'springAccelerationForState = (state) ->'
    stops = list(re.finditer(r'(?m)^[ \t]+return state[ \t]*$', source))
    if source.count(start) != 1 or len(stops) != 1:
        raise ValueError('Unique complete spring helper block required')
    begin = source.index(start)
    end = stops[0].end()
    if end <= begin:
        raise ValueError('Spring helper boundaries are out of order')
    block = source[begin:end]
    if any(character in block for character in "#'\"`"):
        raise ValueError('Whitespace-only comparison requires unquoted uncommented helpers')
    normalized = re.sub(r'\s+', '', block).encode()
    if len(normalized) != 872 or sha(normalized) != '91032f702c37375045a1df7fa857972f6f248b2a3f83fd35e662c7a9c2baed5d':
        raise ValueError('Complete four-helper body differs')
    return normalized


def checked_reference(root, inputs):
    spec = specification(root)
    files = {}
    for name, identity in spec['files'].items():
        body = (inputs / name).read_bytes()
        if sha(body) != identity['sha256'] or len(body) != identity['bytes']:
            raise ValueError('Authentic Framer input changed: ' + name)
        files[name] = body
    if helper_block(files['mit-reference.coffee'].decode()) != helper_block(files['bsd-reference.coffee'].decode()):
        raise ValueError('MIT and older source helpers differ')
    package = json.loads(files['mit-reference-package-json'])
    if (package['name'], package['version'], package['license']) != ('framerjs', '3.0.0', 'MIT'):
        raise ValueError('Contemporary package identity differs')
    if files['mit-reference-LICENSE'] != (root / NOTICE).read_bytes():
        raise ValueError('Distributed MIT text differs from actual source reference')
    return spec


def verify_installed(root=ROOT):
    specification(root)
    helper_block((root / PACKET / 'helper-block.coffee').read_text())
    if sha((root / NOTICE).read_bytes()) != NOTICE_SHA:
        raise ValueError('Complete Framer MIT text changed')
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    if [r for r in inventory['components'] if r['id'] == ID] != [component()]:
        raise ValueError('Qualified Framer attribution differs')
    body = (root / PACKET / 'mapping.json').read_bytes()
    if sha(body) != MAPPING_SHA:
        raise ValueError('Pinned emitted Framer mapping changed')


def replay(root, evidence, inputs):
    spec = checked_reference(root, inputs)
    metadata = json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text())
    if (metadata.get('name'), metadata.get('version')) != ('mermaid', '11.17.2'):
        raise ValueError('Unexpected Mermaid identity')
    files = verified_package_files(evidence / 'mermaid-11.17.2.tgz', metadata)
    bundle = (root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js').read_bytes()
    if sha(bundle) != MERMAID_SHA256 or sha(files['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Pinned Mermaid bundle/map changed')
    outer = verified_bundle_map(bundle, files, 'dist/mermaid.min.js')
    if outer['sources'].count(SOURCE_NAME) != 1:
        raise ValueError('Unique mapped Cytoscape source required')
    index = outer['sources'].index(SOURCE_NAME)
    source = outer['sourcesContent'][index]
    if sha(source.encode()) != CYTOSCAPE_SHA256:
        raise ValueError('Credited Cytoscape source changed')
    span = fragment(source, START, END, CREDIT, PROBES)
    counts = fragment_references(mapped_positions(outer, bundle.decode()), index, {ID: span})[ID]
    return {'schema': 1, 'id': ID, 'referenceRevision': REVISION,
            'referenceSpecificationSHA256': SPEC_SHA, 'noticeSHA256': NOTICE_SHA,
            'helperComparison': spec['helperComparison'],
            'shippedMermaidSHA256': MERMAID_SHA256, 'mapSHA256': MERMAID_MAP_SHA256,
            'cytoscapeSHA256': CYTOSCAPE_SHA256, 'fragmentSHA256': span['source_sha256'],
            'firstSourceLine': span['first_line'] + 1, 'endSourceLineExclusive': span['end_line_exclusive'] + 1,
            **counts, 'scope': spec['scope']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path)
    parser.add_argument('--inputs', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if any([args.evidence_dir, args.inputs, args.output]):
        if not all([args.evidence_dir, args.inputs, args.output]):
            parser.error('Full replay requires evidence-dir, inputs and output')
        result = replay(ROOT, args.evidence_dir, args.inputs)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    else:
        verify_installed()
    print('Qualified Framer source and full MIT reference: passed')
