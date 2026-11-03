#!/usr/bin/env python3
"""Offline binding of captured Go source comments to the distributed corpus."""
import argparse
import json
from pathlib import Path

from prepare_go_stdlib_notices import render, sha

MANIFEST = 'compliance/evidence/go-stdlib-source-notices/manifest.json'
NOTICE = 'compliance/licenses/d2--GO-STDLIB-SUPPLEMENTAL.txt'
MANIFEST_SHA = 'd75dfd5102bcbb4a829b3d2b4091aa3e537349d9d76aa1f84ce2be3ab479ae8d'
COMPONENT_SHA = '37466b3c014e7afa0b232ac3a1768d7f0f77e29b9e0a1019fb7e31463b2f58c2'


def verify_installed(root):
    body = (root / MANIFEST).read_bytes()
    if sha(body) != MANIFEST_SHA:
        raise ValueError('captured standard-library manifest changed')
    report = json.loads(body)
    for fragment in report['fragments']:
        if sha(fragment['text'].encode()) != fragment['sha256']:
            raise ValueError('captured comment digest mismatch')
    texts = {row['path']: row['text'].encode() for row in report['root_texts']}
    reconstructed = render(report['fragments'], texts['go/LICENSE'], texts['go/PATENTS'])
    if sha(reconstructed) != report['notice_sha256'] or (root / NOTICE).read_bytes() != reconstructed:
        raise ValueError('complete selected source notices changed')
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    components = [row for row in inventory['components'] if row['id'] == 'd2-go-stdlib-source-notices']
    if len(components) != 1 or sha(json.dumps(components[0], sort_keys=True, separators=(',', ':')).encode()) != COMPONENT_SHA:
        raise ValueError('source-build component differs from qualified attribution')
    if reconstructed.decode().strip() not in (root / 'compliance/generated/THIRD_PARTY_NOTICES.md').read_text():
        raise ValueError('generated notices omit complete selected source text')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    result = verify_installed(args.root)
    print(json.dumps({'standard_packages': result['standard_packages'], 'selected_files': len(result['selected_files']),
                      'supplemental_files': result['supplemental_source_files'], 'status': 'passed'}, sort_keys=True))


if __name__ == '__main__':
    main()
