#!/usr/bin/env python3
"""Verify Thenable's explicit MIT declaration, standard terms and emitted code."""
import argparse
import hashlib
import json
from pathlib import Path

from audit_cytoscape_attribution import (CYTOSCAPE_SHA256, MERMAID_MAP_SHA256,
    MERMAID_SHA256, SOURCE_NAME, fragment, fragment_references)
from source_map_evidence import mapped_positions, verified_bundle_map, verified_package_files

ROOT = Path(__file__).resolve().parents[2]
TERMS = 'compliance/evidence/thenable-mit-declaration/osi-MIT-terms.txt'
TERMS_SHA = '748c15c2a285ef74aec280f2e72bd98482b96bd0e2da0d8f0fde934fa88e2e16'
REFERENCE_SHA = '15d5267aeaa15d3dfeac1ca6a97378189d693d75ee26130afa342b6fcdfb97ed'
COPYRIGHT = 'Copyright (c) 2013-2014 Ralf S. Engelschall (http://engelschall.com)'
DECLARATION = 'Licensed under The MIT License (http://opensource.org/licenses/MIT)'
NOTICE = 'compliance/licenses/cytoscape-thenable--MIT.txt'
ID = 'cytoscape-thenable'
START = 'var STATE_PENDING = 0;'
END = 'var Promise$1 = typeof Promise'
PROBES = ["  this.id = 'Thenable/1.0.7';", "          promise.reject(new TypeError('circular thenable chain'));else _resolve(promise, y);"]


def sha(body):
    return hashlib.sha256(body).hexdigest()


def assemble(terms):
    if sha(terms) != TERMS_SHA:
        raise ValueError('Canonical MIT terms changed')
    # The author explicitly chose MIT and linked these standard terms. This is
    # an assembled notice, never a fabricated upstream standalone LICENSE file.
    return ('Thenable -- Embeddable Minimum Strictly-Compliant Promises/A+ 1.1.1 Thenable\n'
            + COPYRIGHT + '\n' + DECLARATION + '\n\n').encode() + terms


def component(terms):
    return {'id': ID, 'name': 'Ralf S. Engelschall Thenable (via Cytoscape/Mermaid)',
            'kind': 'attribution', 'version': 'Thenable/1.0.7 credited adaptation',
            'upstream': 'https://github.com/rse/thenable', 'licence': 'MIT',
            'copyright': [COPYRIGHT], 'licence_texts': [{'path': NOTICE, 'sha256': sha(assemble(terms)),
                'upstream': 'https://github.com/rse/thenable',
                'upstream_revision': 'b7ee46032b4be96acf74cb188ace7acc39f1613c',
                'upstream_path': 'thenable.js (copyright and explicit MIT declaration)',
                'assembly': 'Original author declaration/copyright plus the verbatim canonical MIT paragraphs linked by that declaration; not an upstream standalone LICENSE file',
                'standard_terms_source': 'https://opensource.org/license/mit',
                'standard_terms_sha256': TERMS_SHA}],
            'provenance': 'verified', 'resolution': 'credited-version; original adaptation revision unspecified',
            'lc': ['LC-01', 'LC-07'], 'evidence': 'compliance/evidence/thenable-mit-declaration/mapping.json',
            'notes': 'Specific fallback code probes map into shipped Mermaid. The tagged licensed reference confirms the explicit declaration; it is not proof of the exact original adaptation revision or complete Cytoscape attribution.'}


def verify_installed(root):
    terms = (root / TERMS).read_bytes()
    expected = component(terms)
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    if [r for r in inventory['components'] if r['id'] == ID] != [expected]:
        raise ValueError('Installed Thenable attribution differs from reviewed declaration')
    if (root / NOTICE).read_bytes() != assemble(terms):
        raise ValueError('Assembled Thenable notice differs from author and standard terms')


def replay(root, evidence, reference):
    verify_installed(root)
    source = reference.read_bytes()
    if sha(source) != REFERENCE_SHA or b'Licensed under The MIT License <http://opensource.org/licenses/MIT>' not in source:
        raise ValueError('Authentic Thenable reference/declaration changed')
    metadata = json.loads((evidence / 'mermaid-11.17.2-registry.json').read_text())
    files = verified_package_files(evidence / 'mermaid-11.17.2.tgz', metadata)
    bundle = (root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js').read_bytes()
    if sha(bundle) != MERMAID_SHA256 or sha(files['dist/mermaid.min.js.map']) != MERMAID_MAP_SHA256:
        raise ValueError('Pinned Mermaid bundle/map changed')
    outer = verified_bundle_map(bundle, files, 'dist/mermaid.min.js')
    if outer['sources'].count(SOURCE_NAME) != 1:
        raise ValueError('Ambiguous Cytoscape source identity')
    index = outer['sources'].index(SOURCE_NAME)
    cytoscape = outer['sourcesContent'][index]
    if sha(cytoscape.encode()) != CYTOSCAPE_SHA256 or DECLARATION not in cytoscape:
        raise ValueError('Credited Cytoscape source/declaration changed')
    span = fragment(cytoscape, START, END, COPYRIGHT, PROBES)
    counts = fragment_references(mapped_positions(outer, bundle.decode()), index, {ID: span})[ID]
    return {'schema': 1, 'id': ID, 'reference_revision': 'b7ee46032b4be96acf74cb188ace7acc39f1613c',
            'reference_sha256': REFERENCE_SHA, 'shipped_mermaid_sha256': MERMAID_SHA256,
            'source_sha256': CYTOSCAPE_SHA256, 'first_source_line': span['first_line'] + 1,
            'end_source_line_exclusive': span['end_line_exclusive'] + 1, 'fragment_sha256': span['source_sha256'],
            **counts, 'canonical_terms_sha256': TERMS_SHA, 'assembled_notice_sha256': sha((root / NOTICE).read_bytes()),
            'scope': 'Declared standard MIT notice assembly; not an upstream standalone license file, exact original adaptation revision or complete embedded-code audit'}


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
        print('Declared Thenable notice: passed')


if __name__ == '__main__':
    main()
