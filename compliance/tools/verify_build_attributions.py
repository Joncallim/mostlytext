#!/usr/bin/env python3
"""Verify conservative Rough.js/D2 source-build notices, offline and read-only."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
import zipfile

from source_map_evidence import verified_package_files
from verify_d2_offer import verify as verify_offer

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = 'compliance/evidence/nested-build-attribution/manifest.json'
MANIFEST_SHA = 'a69a91d9d6472b0c6307a05f3ba532b831ac12819d7e7572e705ca94dbe0d019'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_installed(root):
    raw = (root / MANIFEST).read_bytes()
    require(sha(raw) == MANIFEST_SHA, 'Reviewed build-attribution manifest changed')
    report = json.loads(raw)
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    expected = report['records']
    actual = [c for c in inventory['components'] if c['id'].startswith(('rough-build-', 'd2-build-', 'renderer-build-'))]
    require(sorted(actual, key=lambda c: c['id']) == sorted(expected, key=lambda c: c['id']),
            'Installed build attribution differs from reviewed evidence')
    for row in expected:
        for text in row['licence_texts']:
            body = (root / text['path']).read_bytes()
            require(sha(body) == text['sha256'], 'Distributed build notice changed')
            body.decode('utf-8', errors='strict')
    for path, key in [('compliance/evidence/d2-0.1.33/source-graph.json', 'd2_graph_sha256'),
                      ('compliance/evidence/mermaid-11.17.2/module-notice-map.json', 'mermaid_mapping_sha256'),
                      ('compliance/evidence/viz-js-3.30.0/source-audit.json', 'graphviz_source_audit_sha256')]:
        require(sha((root / path).read_bytes()) == report['inputs'][key], 'Source graph changed')
    return report


def verify_inputs(root, rough_inputs, mermaid_inputs, d2_archive, graphviz_inputs):
    report = verify_installed(root)
    lock_bytes = (rough_inputs / 'rough-package-lock.json').read_bytes()
    require(sha(lock_bytes) == report['inputs']['rough_lock_sha256'], 'Publisher Rough lock changed')
    lock = json.loads(lock_bytes)
    p = mermaid_inputs / 'npm-packages/roughjs@4.6.6'
    mapped = json.loads((root / 'compliance/evidence/mermaid-11.17.2/module-notice-map.json').read_text())
    mapped_rough = next(r for r in mapped['packages'] if r['name'] == 'roughjs')
    require(sha((p / 'package.tgz').read_bytes()) == mapped_rough['tarball_sha256'], 'Mapped Rough archive changed')
    rough = verified_package_files(p / 'package.tgz', json.loads((p / 'registry.json').read_text()))
    by_id = {r['id']: r for r in report['records']}
    for item in report['evidence'][:4]:
        row = by_id[item['id']]
        name = item['id'].removeprefix('rough-build-')
        version = row['version'].removeprefix('publisher source-build input ')
        p = rough_inputs / (name + '@' + version)
        raw = (p / 'registry.json').read_bytes()
        require(sha(raw) == item['registry_sha256'], 'Nested registry changed')
        require(sha((p / 'package.tgz').read_bytes()) == item['archive_sha256'], 'Nested package changed')
        meta = json.loads(raw)
        require((meta['name'], meta['version']) == (name, version), 'Nested package identity changed')
        files = verified_package_files(p / 'package.tgz', meta)
        pin = lock['packages']['node_modules/' + name]
        require(pin['version'] == version and pin['integrity'] == meta['dist']['integrity']
                and pin['resolved'] == item['archive_url'], 'Publisher dependency pin differs')
        source = rough[item['source_import_path']]
        require(sha(source) == item['source_import_sha256'] and name.encode() in source, 'Source import changed')
        require(files['LICENSE'] == (root / row['licence_texts'][0]['path']).read_bytes(), 'Nested licence differs')
    result = verify_offer(d2_archive, root / 'compliance/evidence/d2-0.1.33/source-graph.json',
                          root / 'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js',
                          root / 'compliance/evidence/d2-0.1.33/offer-manifest.json')
    require(result['archive_sha256'] == report['inputs']['d2_review_archive_sha256'], 'D2 review archive changed')
    with tarfile.open(d2_archive) as archive:
        for item in report['evidence'][4:20]:
            row = by_id[item['id']]
            source = archive.extractfile(item['review_bundle_member']).read()
            require(sha(source) == item['source_zip_sha256'], 'D2 module archive changed')
            with zipfile.ZipFile(io.BytesIO(source)) as zipped:
                prefix = item['module_path'] + '@' + item['module_version'] + '/'
                for text in row['licence_texts']:
                    original = zipped.read(prefix + text['upstream_path'])
                    distributed = (root / text['path']).read_bytes()
                    if text.get('source_encoding'):
                        require(sha(original) == text['upstream_sha256'], 'Encoded original notice changed')
                        require(distributed.decode('utf-8').encode(text['source_encoding']) == original,
                                'Notice transcoding is not text preserving')
                    else:
                        require(original == distributed, 'D2 source licence differs from distributed notice')
    bison = by_id['renderer-build-bison-skeleton']
    evidence = report['evidence'][20]
    graphviz_archive = graphviz_inputs / 'graphviz-16.0.0.tar.gz'
    require(sha(graphviz_archive.read_bytes()) == evidence['graphviz_archive_sha256'], 'Graphviz source archive changed')
    with tarfile.open(graphviz_archive) as archive:
        for path, expected_hash in evidence['source_files'].items():
            body = archive.extractfile('graphviz-16.0.0/' + path).read()
            require(sha(body) == expected_hash, 'Graphviz parser/build source changed')
            if path.endswith('.c'):
                require(body[:evidence['notice_bytes']] == (root / bison['licence_texts'][0]['path']).read_bytes(),
                        'Bison copyright/exception header differs')
    require((rough_inputs / 'Bison-COPYING').read_bytes() == (root / bison['licence_texts'][1]['path']).read_bytes(),
            'Bison full license differs from reference')
    for text in by_id['renderer-build-emscripten']['licence_texts']:
        require((rough_inputs / text['reference_file']).read_bytes() == (root / text['path']).read_bytes(),
                'Compiler root notice differs from source reference')
    return {'rough_build_notices': 4, 'd2_build_notices': 16, 'renderer_build_reference_notices': 2, 'freetype_encoding_roundtrip': True,
            'complete_embedded_attribution': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--rough-inputs', type=Path)
    parser.add_argument('--mermaid-inputs', type=Path)
    parser.add_argument('--d2-archive', type=Path)
    parser.add_argument('--graphviz-inputs', type=Path)
    args = parser.parse_args()
    paths = [args.rough_inputs, args.mermaid_inputs, args.d2_archive, args.graphviz_inputs]
    if any(paths) and not all(paths):
        parser.error('full replay needs all four input locations')
    if all(paths):
        print(json.dumps(verify_inputs(args.root, *paths), indent=2))
    else:
        print(json.dumps({'installed_build_attributions': len(verify_installed(args.root)['records'])}))


if __name__ == '__main__':
    main()
