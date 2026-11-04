#!/usr/bin/env python3
"""Assemble or verify an unpublished Graphviz corresponding-source review package.

This package deliberately retains a review-only status. In particular compiler
runtime completeness, independent provenance review, approval and publication
are not established by packaging the already checked inputs.
"""
import argparse
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile

import verify_libcxx_notices
import verify_viz_renderer

ROOT = Path(__file__).resolve().parents[2]
LIMITS = ('Local source-review package only. Not approved as the complete corresponding-source offer.\n'
          'Includes exact publisher Graphviz/Viz/Expat source archives and npm output, source-build\n'
          'records, current notices and reproduction instructions. No application binary, signing\n'
          'credential or private file is included. The npm package contains the already-public\n'
          'JavaScript/WebAssembly renderer, not a MostlyText application.\n'
          'Remaining: independent source/build and embedded/runtime attribution review, exact\n'
          'compiler/sysroot/build-tool inputs where required, explicit source-only publication\n'
          'authorization, stable hosting and anonymous retrieval. Do not mark source_offer verified.\n'
          'Emscripten root notices do not complete musl/libc++/compiler-rt per-file notice coverage.\n'
          'Included image/reproduction/link receipts are review evidence, not a self-contained\n'
          'compiler environment or approval of final retained-code/source/rights completeness.\n'
          'The source-only publication authorization in compliance/ARCHIVE_PLAN.md still applies.\n')

REPRODUCTION_FILES = {
    'viz-compiler-image': ('README.md', 'manifest.json', 'index.json', 'amd64-manifest.json',
                           'amd64-config.json', 'layer-verification.json', 'selected-files.json'),
    'graphviz-backend-reproduction': ('README.md', 'result.json', 'upstream-Dockerfile', 'UPSTREAM-LICENSE.txt'),
    'viz-renderer-reproduction': ('README.md', 'result.json', 'node-reference.json', 'npm-publisher.json',
                                 'package-lock.json', 'dependencies.json', 'SHASUMS256.txt'),
    'graphviz-link-inputs': ('README.md', 'result.json', 'backend.map', 'why-extract.tsv'),
    'libcxx-image-notices': ('README.md', 'manifest.json'),
}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def add_body(bodies, name, body):
    if name in bodies:
        raise ValueError('Source-review destination collision: ' + name)
    bodies[name] = body


def reproduction_evidence(root):
    # These existing validators bind the complete dependency chains and shipped
    # renderer. Copy only the explicit review allowlist after they succeed.
    verify_libcxx_notices.verify(root)
    verify_viz_renderer.verify(root)
    return {'evidence/reproduction/compliance/evidence/' + folder + '/' + name:
            (root / 'compliance/evidence' / folder / name).read_bytes()
            for folder, names in REPRODUCTION_FILES.items() for name in names}


def payload(root, inputs):
    path = root / 'compliance/evidence/viz-js-3.30.0/audit-source-inputs.py'
    spec = importlib.util.spec_from_file_location('graphviz_source_inputs', path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    report = audit.audit(inputs, root)
    expected = json.loads((root / 'compliance/evidence/viz-js-3.30.0/source-audit.json').read_text())
    if report != expected:
        raise ValueError('Graphviz source audit differs from committed report')
    bodies = {'README.txt': LIMITS.encode()}
    bodies.update(reproduction_evidence(root))
    for name in audit.ARCHIVES:
        bodies['upstream/' + name] = (inputs / name).read_bytes()
    for name in ['source-audit.json', 'downloads.json', 'audit-source-inputs.py']:
        bodies['evidence/' + name] = (root / 'compliance/evidence/viz-js-3.30.0' / name).read_bytes()
    bodies['evidence/ARCHIVE_PLAN.md'] = (root / 'compliance/ARCHIVE_PLAN.md').read_bytes()
    for name in ['compliance/evidence/compiler-rt-source-notices/manifest.json',
                 'compliance/tools/verify_compiler_rt_notices.py']:
        bodies['evidence/compiler-rt/' + Path(name).name] = (root / name).read_bytes()
    for name in ['THIRD_PARTY_NOTICES.md', 'sbom.cdx.json']:
        bodies['distribution-snapshot/' + name] = (root / 'compliance/generated' / name).read_bytes()
    inv = json.loads((root / 'compliance/inventory.json').read_text())
    ids = {'viz-js', 'expat', 'graphviz-rbtree', 'graphviz-ellipse-maisonobe',
           'graphviz-randomkit', 'renderer-build-bison-skeleton', 'renderer-build-emscripten',
           'compiler-rt-publisher-root-notices', 'libcxx-recorded-image-root-notices', 'libcxxabi-recorded-image-root-notices'}
    selected = [r for r in inv['components'] if r['id'] in ids]
    if {r['id'] for r in selected} != ids:
        raise ValueError('Expected Graphviz and nested source notice records')
    bodies['evidence/selected-inventory.json'] = (json.dumps(selected, indent=2, sort_keys=True) + '\n').encode()
    for row in selected:
        for text in row['licence_texts']:
            body = (root / text['path']).read_bytes()
            if sha(body) != text['sha256']:
                raise ValueError('Source-review notice digest changed')
            add_body(bodies, 'notices/' + Path(text['path']).name, body)
    manifest = {'schema': 1, 'status': 'local-review-only; incomplete approval/publication gates',
                'graphviz_revision': audit.GRAPHVIZ_REVISION, 'viz_revision': audit.VIZ_REVISION,
                'expat_revision': audit.EXPAT_REVISION,
                'files': [{'path': k, 'size': len(v), 'sha256': sha(v)} for k, v in sorted(bodies.items())]}
    bodies['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    return bodies, manifest


def encode(bodies):
    result = io.BytesIO()
    with gzip.GzipFile(fileobj=result, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for name, body in sorted(bodies.items()):
                entry = tarfile.TarInfo(name)
                entry.size, entry.mode, entry.mtime = len(body), 0o644, 0
                archive.addfile(entry, io.BytesIO(body))
    return result.getvalue()


def verify_archive(path, bodies):
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        names = [m.name for m in members]
        if len(set(names)) != len(names) or set(names) != set(bodies):
            raise ValueError('Source-review member set differs or is duplicated')
        for member in members:
            if not member.isfile() or archive.extractfile(member).read() != bodies[member.name]:
                raise ValueError('Source-review member type or contents changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bodies, manifest = payload(args.root, args.inputs)
    if not args.verify_only:
        body = encode(bodies)
        if args.output.exists() and args.output.read_bytes() != body:
            raise ValueError('Refusing to overwrite a different prepared source package')
        if not args.output.exists():
            with args.output.open('xb') as output:
                output.write(body)
    verify_archive(args.output, bodies)
    print(json.dumps({'archive_sha256': sha(args.output.read_bytes()), 'files': len(manifest['files']),
                      'status': manifest['status'], 'manifest': manifest}, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
