#!/usr/bin/env python3
"""Match link-object basenames to pinned source archives, without claiming identity."""

import hashlib
import json
import re
import tarfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCES = {
    'graphviz': ('graphviz-16.0.0.tar.gz', '36a1de1aaf5a2023b14f95170a5f8f0b12522d1c305b517fc261966597050749'),
    'expat': ('expat-2.8.4.tar.gz', 'b8ece2437692dad44d851c4532723390a5a330990007706be9c8d2b90d294f36'),
    'emscripten': ('emscripten-263db4cf.tar.gz', 'd34ff1cb0ab99f74c0aefd4641f7a514754f2f6218d540d135ef1cf8467b08ba'),
}
EXT = {'.c', '.cc', '.cpp', '.cxx', '.S', '.s', '.l', '.y'}


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs', type=Path, required=True)
    args = parser.parse_args()
    source_paths = {}
    source_details = {}
    for family, (name, digest) in SOURCES.items():
        raw = (args.inputs / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError(f'{name}: changed source archive')
        with tarfile.open(args.inputs / name, 'r:gz') as tar:
            source_details[family] = {}
            for member in tar:
                if not member.isfile() or '/' not in member.name:
                    continue
                path = member.name.split('/', 1)[1]
                if Path(path).suffix not in EXT:
                    continue
                body = tar.extractfile(member).read()
                header = body[:4096].decode('utf-8', 'replace')
                spdx = sorted(set(re.findall(r'SPDX-License-Identifier:\s*([^\r\n*]+)', header)))
                signals = [term for term in ('Copyright', 'copyright', 'Permission is hereby granted',
                                             'All rights reserved', 'public domain', 'GNU General Public',
                                             'University of Illinois', 'Apache License', 'MIT License')
                           if term in header]
                source_details[family][path] = {'path': path, 'sha256': hashlib.sha256(body).hexdigest(),
                                                'spdx_header': spdx, 'notice_signals': signals}
            source_paths[family] = list(source_details[family])
    union = json.loads((ROOT / 'union-review.json').read_text())
    if union['union'] != 489:
        raise ValueError('unexpected union index')
    out = []
    for item in union['members']:
        family = item['source_family']
        archive = 'graphviz' if family == 'graphviz' else 'expat' if family == 'expat' else 'emscripten'
        prefix = {'graphviz': '', 'expat': 'lib/', 'compiler-rt': 'system/lib/compiler-rt/',
                  'libc++': 'system/lib/libcxx/', 'libc++abi': 'system/lib/libcxxabi/',
                  'emscripten-sysroot': 'system/lib/'}[family]
        stem = item['member'][:-2]
        if '_la-' in stem:
            stem = stem.split('_la-', 1)[1]
        elif stem.startswith(('lt1-', 'lt2-')):
            stem = stem.split('-', 1)[1]
        elif stem.endswith('__1'):
            stem = stem[:-3]
        candidates = sorted(p for p in source_paths[archive]
                            if p.startswith(prefix) and Path(p).suffix in EXT and Path(p).stem == stem)
        out.append({'archive': item['archive'], 'member': item['member'],
                    'source_archive': SOURCES[archive][0],
                    'basename_candidates': [source_details[archive][p] for p in candidates],
                    'status': 'candidate-only; build-file mapping and per-file terms required'})
    result = {'schema': 1, 'scope': 'basename search in pinned source archives, not compiler provenance',
              'source_archives': {k: {'name': v[0], 'sha256': v[1]} for k, v in SOURCES.items()},
              'counts': dict(sorted(Counter('none' if not x['basename_candidates'] else
                                             'unique' if len(x['basename_candidates']) == 1 else 'multiple'
                                             for x in out).items())), 'members': out}
    (ROOT / 'source-candidates.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
