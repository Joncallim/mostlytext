#!/usr/bin/env python3
"""Extract conservative notices for possible compiler-image source inputs."""

import argparse
import hashlib
import json
import re
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
SOURCE_SHA = 'd34ff1cb0ab99f74c0aefd4641f7a514754f2f6218d540d135ef1cf8467b08ba'
PREFIX = 'emscripten-263db4cffa6f9fc2ec514a70abac81362ea41849/'
DIRECT = {
    'system/lib/llvm-libc/LICENSE.TXT': 'graphviz-llvm-libc--LICENSE.txt',
    'system/lib/mimalloc/LICENSE': 'graphviz-mimalloc--MIT.txt',
}
QSORT = 'system/lib/libc/musl/src/stdlib/qsort.c'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def read_source(archive, paths):
    result = {}
    with tarfile.open(archive, 'r:gz') as source:
        for member in source:
            if member.name.startswith(PREFIX) and member.name[len(PREFIX):] in paths:
                if not member.isfile():
                    raise ValueError('selected source is not a regular file')
                path = member.name[len(PREFIX):]
                if path in result:
                    raise ValueError('duplicate source path')
                result[path] = source.extractfile(member).read()
    if set(result) != paths:
        raise ValueError('selected source path missing from pinned archive')
    return result


def prepare(archive):
    if sha(archive.read_bytes()) != SOURCE_SHA:
        raise ValueError('Emscripten source archive changed')
    rows = json.loads((EVIDENCE / 'source-candidates.json').read_text())['members']
    candidates = {c['path']: c['sha256'] for row in rows for c in row['basename_candidates']}
    math_paths = sorted(path for path in candidates if path.startswith('system/lib/libc/musl/src/math/'))
    paths = set(DIRECT) | {QSORT} | set(math_paths)
    source = read_source(archive, paths)
    for path in paths & candidates.keys():
        if sha(source[path]) != candidates[path]:
            raise ValueError('candidate source digest changed: ' + path)
    if sum(path.startswith('system/lib/llvm-libc/') for path in candidates) != 110:
        raise ValueError('LLVM libc candidate set changed')
    if 'system/lib/mimalloc/src/libc.c' not in candidates:
        raise ValueError('mimalloc candidate missing')
    output = {name: source[path] for path, name in DIRECT.items()}
    qsort_comments = list(re.finditer(rb'/\*[\s\S]*?\*/', source[QSORT][:5000]))
    if len(qsort_comments) < 2 or b'Permission is hereby granted' not in qsort_comments[0].group():
        raise ValueError('musl qsort permission text changed')
    if b'Minor changes by Rich Felker' not in qsort_comments[1].group():
        raise ValueError('musl qsort modification text changed')
    output['graphviz-musl-qsort--MIT.txt'] = source[QSORT][:qsort_comments[1].end()] + b'\n'
    groups = {}
    for path in math_paths:
        comments = [match.group() for match in re.finditer(rb'/\*[\s\S]*?\*/', source[path][:8000])
                    if b'Copyright' in match.group() and b'Sun Microsystems' in match.group()]
        if not comments:
            continue
        if len(comments) != 1 or b'Permission to use, copy, modify, and distribute' not in comments[0]:
            raise ValueError('Sun math notice changed: ' + path)
        groups.setdefault(comments[0], []).append(path)
    if sum(map(len, groups.values())) != 17 or len(groups) != 7:
        raise ValueError('Sun math candidate notice set changed')
    math_mapping = []
    for number, (body, members) in enumerate(sorted(groups.items(), key=lambda pair: sha(pair[0])), 1):
        name = f'graphviz-musl-sun-math--{number:02d}.txt'
        output[name] = body + b'\n'
        math_mapping.append({'notice': name, 'notice_sha256': sha(output[name]),
                             'source_paths': sorted(members),
                             'source_sha256': {path: sha(source[path]) for path in sorted(members)}})
    report = {'schema': 1, 'status': 'conservative candidate attribution, not final retained-code proof',
              'source_archive_sha256': SOURCE_SHA, 'source_commit': PREFIX.rstrip('/').split('-', 1)[1],
              'llvm_libc_candidate_source_files': 110, 'mimalloc_candidate_source_files': 1,
              'qsort': {'source_path': QSORT, 'source_sha256': sha(source[QSORT]),
                        'notice': 'graphviz-musl-qsort--MIT.txt',
                        'notice_sha256': sha(output['graphviz-musl-qsort--MIT.txt'])},
              'direct_notices': {path: {'notice': name, 'source_sha256': sha(source[path]),
                                        'notice_sha256': sha(output[name])}
                                 for path, name in DIRECT.items()},
              'sun_math': math_mapping,
              'limitation': 'The map names possible pre-optimization inputs; exact selected objects, generated glue, inline headers and all other per-file terms remain for review.'}
    return output, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    files, report = prepare(args.source)
    target = ROOT / 'compliance/licenses'
    for name, body in files.items():
        path = target / name
        if path.exists() and path.read_bytes() != body:
            raise ValueError('refusing to overwrite changed notice ' + name)
        path.write_bytes(body)
    (EVIDENCE / 'candidate-notices.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'notice_files': len(files), 'sun_math_candidate_files': 17,
                      'report_sha256': sha((EVIDENCE / 'candidate-notices.json').read_bytes())}, indent=2))


if __name__ == '__main__':
    main()
