#!/usr/bin/env python3
"""Check the pinned receipt of the complete, locally reproduced parser JS lane.

Offline checks protect the captured result; they do not rerun the upstream build
or turn a technical reproduction into independent IP/native/release acceptance.
"""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/parser-runtime-reproduction'
MANIFEST_SHA = '912cbbff1784e95298f882dade1bf22e5617d06f1bb17e4a5c9200d1f2f76088'
SOURCE = '293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4'
ARCHIVE = '97eef1a4c37110e4836b6eb8dd6a348d989efb370a7672831df01042a7c323f4'
VSCODE_ARCHIVE = 'c6ec752d7a4858237389b23fb4d5ac05c2f1f606071cd212a9b54730e43cfc54'
MAP_SHA = '6183e8177380457abbe5522f173ac844da1a4ae6609408c7d5de727a306609cb'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def validate_receipt(data):
    expected = {'sourceCommit': SOURCE, 'publisherArchiveSHA256': ARCHIVE,
                'node': '24.16.0', 'pnpm': '10.30.3', 'esbuild': '0.25.12',
                'comparedMembers': 192, 'javascriptMembers': 96, 'mapMembers': 96,
                'identicalMembers': 192, 'publisherSourceFilesVerified': 1753}
    for key, value in expected.items():
        if type(data.get(key)) is not type(value) or data[key] != value:
            raise ValueError('Parser reproduction identity/count changed: ' + key)
    if any(data.get(key) != [] for key in ('missing', 'different', 'changedPublisherSources')):
        raise ValueError('Parser reproduction contains missing/different/source changes')
    rows = data.get('members')
    if not isinstance(rows, list) or len(rows) != 192:
        raise ValueError('Complete parser member set required')
    names, scripts, maps = set(), set(), set()
    for row in rows:
        name = row.get('member', '')
        if (not isinstance(name, str) or not name.startswith('dist/')
                or '..' in name.split('/') or name in names
                or not name.endswith(('.mjs', '.mjs.map'))):
            raise ValueError('Invalid/duplicate parser member')
        names.add(name)
        (scripts if name.endswith('.mjs') else maps).add(name)
        original, rebuilt = row.get('publishedSHA256'), row.get('rebuiltSHA256')
        if (not isinstance(original, str) or not re.fullmatch('[0-9a-f]{64}', original)
                or rebuilt != original or row.get('byteIdentical') is not True
                or type(row.get('bytes')) is not int or row['bytes'] <= 0):
            raise ValueError('Published/rebuilt parser member differs')
    if len(scripts) != 96 or maps != {name + '.map' for name in scripts}:
        raise ValueError('Complete JavaScript/map pairing required')
    return {row['member']: row for row in rows}


def verify_installed(root=ROOT):
    folder = root / PACKET
    try:
        raw = (folder / 'manifest.json').read_bytes()
    except FileNotFoundError as error:
        raise ValueError('Pinned parser reproduction proof missing') from error
    if sha(raw) != MANIFEST_SHA:
        raise ValueError('Pinned parser reproduction manifest changed')
    manifest = json.loads(raw)
    for name, digest in manifest['files'].items():
        if '/' in name or name in ('.', '..') or sha((folder / name).read_bytes()) != digest:
            raise ValueError('Pinned parser reproduction evidence changed: ' + name)
    receipt = json.loads((folder / 'reproduction.json').read_text())
    rows = validate_receipt(receipt)
    publisher = json.loads((root / 'compliance/evidence/parser-publisher-provenance/manifest.json').read_text())
    if (publisher['source_commit'] != SOURCE or publisher['archive']['sha256'] != ARCHIVE
            or publisher['declared_build_inputs'] != {'langium': '4.2.1', 'vscode-uri': '3.1.0', 'root_esbuild': '0.25.12'}):
        raise ValueError('Reproduction/publisher source binding changed')
    original = {item['path']: item['sha256'] for item in publisher['source_inputs']}
    expected_inputs = {'.github/workflows/release.yml', 'pnpm-lock.yaml', 'package.json',
                       'packages/parser/package.json', '.esbuild/build.ts', 'packages/parser/scripts/prepack.ts'}
    if (set(original) != expected_inputs or len(publisher['source_inputs']) != 6
            or any(manifest['sourceInputs'].get(name) != digest for name, digest in original.items())):
        raise ValueError('Reproduction/publisher source-input hashes differ')
    source_hashes = json.loads((folder / 'publisher-source-hashes.json').read_text())
    if len(source_hashes) != 1753 or any(source_hashes.get(name) != digest for name, digest in manifest['sourceInputs'].items()):
        raise ValueError('Complete unchanged publisher source index required')
    if manifest['vscodeUri'] != {'version': '3.1.0', 'archiveSHA256': VSCODE_ARCHIVE}:
        raise ValueError('Reproduced vscode-uri input changed')
    raw_map = (root / 'compliance/evidence/mermaid-11.17.2/module-notice-map.json').read_bytes()
    if sha(raw_map) != MAP_SHA:
        raise ValueError('Original composed Mermaid mapping changed')
    # Every parser source actually reached by the outer map must be among the
    # complete reproduced outputs, not just an unrelated successful JS build.
    report = json.loads(raw_map)
    shipped = root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js'
    if sha(shipped.read_bytes()) != report['bundle']['sha256']:
        raise ValueError('Current shipped Mermaid differs from reproduced linkage')
    linked = report['parser_chunk_links']
    if len(linked) != 32:
        raise ValueError('Expected complete shipped parser linkage')
    for item in linked:
        member = item['source'].removeprefix('../../parser/')
        if (member not in rows or rows[member]['publishedSHA256'] != item['sha256']
                or rows[member + '.map']['publishedSHA256'] != item['map_sha256']):
            raise ValueError('Reproduced member does not bind shipped parser source')
    return manifest


if __name__ == '__main__':
    verify_installed()
    print('Complete parser JS/map reproduction receipt: passed')
