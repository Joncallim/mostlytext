#!/usr/bin/env python3
"""Install or verify captured Mermaid package notices without executing packages.

The reviewed map is pinned independently of supplied registry data. An optional
full replay proves mapped inclusion; package identity, archive integrity and every
selected notice byte are always checked. Content-only candidates stay qualified;
the specific reproduced publisher input requires its separate pinned proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

from audit_mermaid_bundle import audit
from source_map_evidence import verified_package_files
from verify_parser_reproduction import verify_installed as checked_reproduction, VSCODE_ARCHIVE, PACKET

ROOT = Path(__file__).resolve().parents[2]
MAP_PATH = 'compliance/evidence/mermaid-11.17.2/module-notice-map.json'
MAP_SHA = '6183e8177380457abbe5522f173ac844da1a4ae6609408c7d5de727a306609cb'
SHIPPED = 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js'
CANDIDATES = {'vscode-uri', 'path-browserify'}
PREFIX = 'mermaid-package-'


def sha(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def package_id(row: dict) -> str:
    return PREFIX + re.sub(r'[^a-zA-Z0-9.-]+', '-', row['name']).strip('-') + '-' + row['version']


def checked_map(root: Path) -> dict:
    body = (root / MAP_PATH).read_bytes()
    if sha(body) != MAP_SHA:
        raise ValueError('Reviewed Mermaid mapping digest changed')
    return json.loads(body)


def extract_text(files: dict[str, bytes], spec: dict) -> bytes:
    body = files[spec['archive_path']]
    if 'byte_start' in spec:
        if sha(body) != spec['archive_file_sha256']:
            raise ValueError('README container digest changed')
        start, end = spec['byte_start'], spec['byte_end_exclusive']
        if not 0 <= start < end <= len(body):
            raise ValueError('Invalid notice byte range')
        body = body[start:end]
    if len(body) != spec['bytes'] or sha(body) != spec['sha256']:
        raise ValueError('Captured notice bytes changed')
    body.decode('utf-8', errors='strict')
    return body


def component(row: dict, texts: list[dict]) -> dict:
    candidate = row['name'] in CANDIDATES
    expression = 'Apache-2.0' if row['name'] == 'dompurify' else row['package_license_expression']
    # The complete verbatim text carries all copyright holders, including texts
    # with several inherited licences. Do not guess authors from package metadata.
    result = {
        'id': package_id(row),
        'name': row['name'] + (' (content-matched reference via Mermaid; original version unresolved)' if candidate else ' (via Mermaid)'),
        'kind': 'attribution',
        'version': ('original unresolved; content matches ' if candidate else '') + row['version'],
        'upstream': row['registry_url'],
        'licence': expression,
        'copyright': ['Copyright holders and original notices are reproduced verbatim in the complete licence text below.'],
        'licence_texts': texts,
        'provenance': 'verified',
        'resolution': 'content-match-only; original resolution unresolved' if candidate else 'exact-mapped-input',
        'lc': ['LC-01', 'LC-07'],
        'evidence': MAP_PATH,
        'notes': 'Mapped generated source, not full package inclusion or complete embedded-code attribution. ' + row['version_authority'],
    }
    if not candidate:
        result['npm'] = row['name'] + '@' + row['version']
    return result


def projected_texts(row: dict) -> list[dict]:
    result = []
    for number, spec in enumerate(row['package_license_texts'], 1):
        text = {'path': 'compliance/licenses/' + package_id(row) + '--' + str(number) + '.txt',
                'sha256': spec['sha256'], 'upstream': row['tarball_url'],
                'upstream_path': spec['archive_path'], 'upstream_archive_sha256': row['tarball_sha256']}
        if 'byte_start' in spec:
            text.update({key: spec[key] for key in ('byte_start', 'byte_end_exclusive', 'archive_file_sha256')})
        result.append(text)
    return result


def reproduced_component(row: dict, texts: list[dict], proof: dict) -> dict:
    result = component(row, texts)
    if row['name'] == 'vscode-uri' and row['version'] == '3.1.0':
        if (row.get('tarball_sha256') != VSCODE_ARCHIVE
                or proof.get('vscodeUri') != {'version': '3.1.0', 'archiveSHA256': VSCODE_ARCHIVE}):
            raise ValueError('Reproduced publisher input identity differs')
        result.update(name='vscode-uri (reproduced publisher input via Mermaid)', version='3.1.0',
                      resolution='signed-publisher-input-and-reproduced-parser-build', npm='vscode-uri@3.1.0',
                      evidence=PACKET + '/manifest.json',
                      notes='The signed publisher source, frozen lock and complete byte-identical parser JS/map reproduction establish this outer build input. The original content-only report is retained. This is not full package inclusion or proof of every earlier nested build or licence obligation.')
    return result


def verify_installed(root: Path) -> None:
    """Enforce reviewed attribution projection in ordinary offline CI, without raw archives."""
    report = checked_map(root)
    proof = checked_reproduction(root)
    if sha((root / SHIPPED).read_bytes()) != report['bundle']['sha256']:
        raise ValueError('Shipped Mermaid changed')
    records = []
    for row in report['packages']:
        if row['name'] == 'cytoscape':
            continue
        texts = projected_texts(row)
        records.append(reproduced_component(row, texts, proof))
        for spec, text in zip(row['package_license_texts'], texts):
            body = (root / text['path']).read_bytes()
            if len(body) != spec['bytes'] or sha(body) != spec['sha256']:
                raise ValueError('Distributed package notice differs: ' + text['path'])
    verify_inventory(json.loads((root / 'compliance/inventory.json').read_text()), records)


def expected(root: Path, evidence: Path, replay: bool = False) -> tuple[list[dict], dict[str, bytes]]:
    report = checked_map(root)
    proof = checked_reproduction(root)
    if sha((root / SHIPPED).read_bytes()) != report['bundle']['sha256']:
        raise ValueError('Shipped Mermaid changed')
    if replay and audit(evidence, root / SHIPPED) != report:
        raise ValueError('Full source-map replay differs from reviewed mapping')
    records, outputs = [], {}
    for row in report['packages']:
        if row['name'] == 'cytoscape':
            continue  # Existing own-code notice is separately checked below.
        folder = evidence / 'npm-packages' / (row['name'].replace('@', '').replace('/', '__') + '@' + row['version'])
        raw = (folder / 'registry.json').read_bytes()
        archive = folder / 'package.tgz'
        if sha(raw) != row['registry_sha256'] or sha(archive.read_bytes()) != row['tarball_sha256']:
            raise ValueError('Pinned package evidence changed: ' + row['name'])
        metadata = json.loads(raw)
        if (metadata['name'], metadata['version']) != (row['name'], row['version']):
            raise ValueError('Package identity changed')
        files = verified_package_files(archive, metadata)
        texts = projected_texts(row)
        for spec, text in zip(row['package_license_texts'], texts):
            outputs[text['path']] = extract_text(files, spec)
        records.append(reproduced_component(row, texts, proof))
    if len(records) != 73 or len({r['id'] for r in records}) != 73:
        raise ValueError('Expected 73 distinct additional package notices')
    return records, outputs


def verify_inventory(inventory: dict, records: list[dict]) -> None:
    actual = [c for c in inventory['components'] if c['id'].startswith(PREFIX)]
    if sorted(actual, key=lambda c: c['id']) != sorted(records, key=lambda c: c['id']):
        raise ValueError('Installed nested package records differ from reviewed evidence')
    cyto = [c for c in inventory['components'] if c['id'] == 'cytoscape-via-mermaid']
    if len(cyto) != 1 or cyto[0]['licence_texts'][0]['sha256'] != 'eb319c6e6f233607f71e8e2f450391751883cfc0eeb3ca7ef574c13d1d9c2203':
        raise ValueError('Existing Cytoscape own-code notice must be retained')


def run(root: Path, evidence: Path, write: bool, replay: bool) -> dict:
    records, outputs = expected(root, evidence, replay)
    path = root / 'compliance/inventory.json'
    inventory = json.loads(path.read_text())
    if write:
        for name, body in outputs.items():
            (root / name).write_bytes(body)
        inventory['components'] = [c for c in inventory['components'] if not c['id'].startswith(PREFIX)] + records
        path.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + '\n')
    verify_inventory(inventory, records)
    for name, body in outputs.items():
        if (root / name).read_bytes() != body:
            raise ValueError('Distributed package notice differs: ' + name)
    return {'new_package_records': len(records), 'retained_cytoscape_records': 1,
            'candidate_notices_with_unresolved_original_version': sum('content-match-only' in r['resolution'] for r in records),
            'complete_text_files': len(outputs), 'text_bytes': sum(map(len, outputs.values())),
            'full_source_map_replay': replay, 'embedded_attribution_complete': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--replay', action='store_true')
    args = parser.parse_args()
    print(json.dumps(run(args.root, args.evidence_dir, args.write, args.replay), indent=2))


if __name__ == '__main__':
    main()
