#!/usr/bin/env python3
"""Bind conservative compiler-rt root attribution to captured immutable sources."""
import argparse
import ast
import hashlib
import json
from pathlib import Path

MANIFEST = 'compliance/evidence/compiler-rt-source-notices/manifest.json'
MANIFEST_SHA = '92123ce74ad3a929e86c3c9eb952c013b42ed44194f3aae6cd26d66fda0bcf24'
COMPONENT_SHA = '3cd18ec2a64d2e9a67447725c432684ba4dba13d62faf1ca6cd4b24441120394'
COMPONENT = 'compiler-rt-publisher-root-notices'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def verify_installed(root):
    body = (root / MANIFEST).read_bytes()
    if sha(body) != MANIFEST_SHA:
        raise ValueError('captured compiler-runtime manifest changed')
    report = json.loads(body)
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    components = [row for row in inventory['components'] if row['id'] == COMPONENT]
    if len(components) != 1 or sha(json.dumps(components[0], sort_keys=True, separators=(',', ':')).encode()) != COMPONENT_SHA:
        raise ValueError('qualified compiler-runtime attribution changed')
    corpus = (root / 'compliance/generated/THIRD_PARTY_NOTICES.md').read_bytes()
    for record in report['license_texts']:
        text = (root / record['path']).read_bytes()
        if sha(text) != record['sha256']:
            raise ValueError('complete compiler-runtime root text changed')
        if text.strip() not in corpus:
            raise ValueError('generated corpus omits complete compiler-runtime root text')
    audit = json.loads((root / 'compliance/evidence/viz-js-3.30.0/source-audit.json').read_text())
    if (audit['shipped_bundle_sha256'] != report['shipped_renderer_sha256'] or
            audit['backend_publisher_dependencies'][0] != report['publisher_compiler_image'] or
            audit['build_source_sha256']['packages/viz/backend/Dockerfile'] != report['publisher_build_source_sha256']):
        raise ValueError('qualified publisher build binding changed')
    renderer = next(row for row in inventory['components'] if row['id'] == 'viz-js')
    if report['shipped_renderer_sha256'] not in {row['sha256'] for row in renderer['files']}:
        raise ValueError('qualified renderer bytes changed')
    for anchor in report['source_anchors']:
        if sha(anchor['text'].encode()) != anchor['sha256'] or len(anchor['text'].encode()) != anchor['bytes']:
            raise ValueError('captured source anchor changed')
    selection = next(row['text'] for row in report['source_anchors'] if row['text'].startswith('def get_libs_to_link('))
    function = ast.parse(selection).body[0]
    default_calls = [statement.value for statement in function.body if isinstance(statement, ast.Expr)
                     and isinstance(statement.value, ast.Call)]
    if not any(isinstance(call.func, ast.Name) and call.func.id == 'add_library' and call.args
               and isinstance(call.args[0], ast.Constant) and call.args[0].value == 'libcompiler_rt'
               for call in default_calls):
        raise ValueError('normal compiler-runtime selection absent')
    return report


def verify_inputs(report, inputs):
    for record in report['inputs']:
        body = (inputs / record['path'].replace('/', '--')).read_bytes()
        identity = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest()
        if len(body) != record['bytes'] or sha(body) != record['sha256'] or identity != record['git_blob_sha1']:
            raise ValueError('immutable upstream input changed')
        for anchor in report['source_anchors']:
            if anchor['source'] != record['path']:
                continue
            start = anchor['byte_offset']
            if body[start:start + anchor['bytes']] != anchor['text'].encode():
                raise ValueError('source anchor is not at the recorded input offset')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--inputs', type=Path, help='optional retained raw inputs; never executes them')
    args = parser.parse_args()
    report = verify_installed(args.root)
    if args.inputs:
        verify_inputs(report, args.inputs)
    print(json.dumps({'status': 'passed', 'texts': len(report['license_texts']),
                      'source_anchors': len(report['source_anchors']),
                      'upstream_inputs_replayed': args.inputs is not None,
                      'scope': report['status']}, sort_keys=True))


if __name__ == '__main__':
    main()
