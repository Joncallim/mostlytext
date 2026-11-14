#!/usr/bin/env python3
"""Preserve exact scoped headers and CPL text for possible Graphviz link inputs."""

import argparse
import hashlib
import json
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
ARCHIVES = {
    'graphviz': ('graphviz-16.0.0.tar.gz',
                 '36a1de1aaf5a2023b14f95170a5f8f0b12522d1c305b517fc261966597050749',
                 'graphviz-16.0.0/'),
    'expat': ('expat-2.8.4.tar.gz',
              'b8ece2437692dad44d851c4532723390a5a330990007706be9c8d2b90d294f36',
              'expat-2.8.4/'),
    'emscripten': ('emscripten-263db4cf.tar.gz',
                   'd34ff1cb0ab99f74c0aefd4641f7a514754f2f6218d540d135ef1cf8467b08ba',
                   'emscripten-263db4cffa6f9fc2ec514a70abac81362ea41849/'),
}
VPSC_SOURCE = (
    'lib/neatogen/constrained_majorization_ipsep.c',
    'lib/neatogen/quad_prog_vpsc.c',
    'lib/vpsc/block.cpp', 'lib/vpsc/blocks.cpp', 'lib/vpsc/constraint.cpp',
    'lib/vpsc/csolve_VPSC.cpp', 'lib/vpsc/generate-constraints.cpp',
    'lib/vpsc/solve_VPSC.cpp', 'lib/vpsc/variable.cpp',
)
VPSC_HEADERS = ('lib/neatogen/quad_prog_vpsc.h',) + tuple(
    'lib/vpsc/' + name for name in (
        'variable.h', 'csolve_VPSC.h', 'blocks.h', 'solve_VPSC.h',
        'block.h', 'generate-constraints.h', 'constraint.h'))
EXPAT_SOURCE = ('lib/random_getentropy.c', 'lib/xmlparse.c', 'lib/xmlrole.c', 'lib/xmltok.c')
EMSCRIPTEN_SOURCE = tuple('system/lib/libc/' + name for name in (
    'atexit_dummy.c', 'emscripten_get_heap_size.c', 'emscripten_mmap.c',
    'emscripten_syscall_stubs.c', 'emscripten_time.c',
    'emscripten_yield_stub.c', 'mktime.c', 'pthread_sigmask.c', 'raise.c',
    'sbrk.c', 'sigaction.c', 'wasi-helpers.c')) + (
    'system/lib/pthread/library_pthread_stub.c',
    'system/lib/pthread/pthread_self_stub.c',
)
ARM_SOURCE = ('system/lib/libc/musl/src/math/exp.c',
              'system/lib/libc/musl/src/math/exp_data.c')
OUTPUTS = {
    'graphviz-vpsc--SOURCE-HEADERS.txt': ('graphviz', VPSC_SOURCE + VPSC_HEADERS, b'CPL (Common Public License)'),
    'graphviz-expat-file-headers--MIT.txt': ('expat', EXPAT_SOURCE, b'Licensed under the MIT license'),
    'graphviz-emscripten-newer-headers--MIT-NCSA.txt': ('emscripten', EMSCRIPTEN_SOURCE, b'The Emscripten Authors'),
    'graphviz-musl-arm-math--MIT.txt': ('emscripten', ARM_SOURCE, b'Arm Limited'),
}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def selected(archive_path, expected_sha, prefix, paths):
    if sha(archive_path.read_bytes()) != expected_sha:
        raise ValueError('source archive changed: ' + archive_path.name)
    result = {}
    with tarfile.open(archive_path, 'r:gz') as source:
        for path in paths:
            member = source.getmember(prefix + path)
            if not member.isfile() or member.size > 5_000_000:
                raise ValueError('source member is not a bounded regular file: ' + path)
            result[path] = source.extractfile(member).read()
    return result


def first_comment(body, marker):
    start = body.find(b'/*')
    end = body.find(b'*/', start + 2)
    if start != 0 or end < 0 or end > 8_000 or marker not in body[:end]:
        raise ValueError('selected source header or grant changed')
    return body[:end + 2] + b'\n'


def prepare(inputs, emscripten_source):
    paths = {'graphviz': set(VPSC_SOURCE + VPSC_HEADERS + ('cpl1.0.txt',)),
             'expat': set(EXPAT_SOURCE), 'emscripten': set(EMSCRIPTEN_SOURCE + ARM_SOURCE)}
    sources = {}
    for family, (filename, digest, prefix) in ARCHIVES.items():
        archive_path = emscripten_source if family == 'emscripten' else inputs / filename
        sources[family] = selected(archive_path, digest, prefix, paths[family])
    candidates = json.loads((EVIDENCE / 'source-candidates.json').read_text())['members']
    matched = sorted((row['archive'], row['member']) for row in candidates
                     if row['archive'] == 'libgvplugin_neato_layout.a'
                     and any(c['path'] in VPSC_SOURCE for c in row['basename_candidates']))
    if len(matched) != 11:
        raise ValueError('VPSC candidate member set changed')
    for family, expected in (('expat', set(EXPAT_SOURCE)),
                             ('emscripten', set(EMSCRIPTEN_SOURCE + ARM_SOURCE))):
        found = {c['path'] for row in candidates for c in row['basename_candidates']
                 if c['path'] in expected}
        if found != expected:
            raise ValueError(f'{family} candidate source set changed')
    if b'Common Public License Version 1.0' not in sources['graphviz']['cpl1.0.txt']:
        raise ValueError('Graphviz CPL root text changed')
    output = {'graphviz-vpsc--CPL-1.0.txt': sources['graphviz']['cpl1.0.txt']}
    report = {'schema': 1, 'status': 'conservative candidate notices; object selection and rights review open',
              'source_archives': {family: {'filename': row[0], 'sha256': row[1]}
                                  for family, row in ARCHIVES.items()},
              'vpsc_candidate_members': [{'archive': archive, 'member': member}
                                         for archive, member in matched], 'notices': {}}
    report['notices']['graphviz-vpsc--CPL-1.0.txt'] = {
        'sha256': sha(output['graphviz-vpsc--CPL-1.0.txt']),
        'source_paths': ['cpl1.0.txt']}
    for name, (family, members, marker) in OUTPUTS.items():
        chunks = []
        for path in members:
            chunks.append(b'Source: ' + path.encode() + b'\n' + first_comment(sources[family][path], marker))
        output[name] = b'\n'.join(chunks)
        report['notices'][name] = {'sha256': sha(output[name]),
                                   'source_paths': list(members),
                                   'source_sha256': {p: sha(sources[family][p]) for p in members}}
    return output, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--emscripten-source', type=Path, required=True)
    args = parser.parse_args()
    files, report = prepare(args.inputs, args.emscripten_source)
    target = ROOT / 'compliance/licenses'
    for name, body in files.items():
        path = target / name
        if path.exists() and path.read_bytes() != body:
            raise ValueError('refusing to overwrite changed notice: ' + name)
        path.write_bytes(body)
    result = (EVIDENCE / 'additional-notices.json')
    text = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if result.exists() and result.read_text() != text:
        raise ValueError('refusing to overwrite changed notice report')
    result.write_text(text)
    print(json.dumps({'notice_files': len(files), 'source_headers': sum(len(v[1]) for v in OUTPUTS.values()),
                      'report_sha256': sha(text.encode())}, indent=2))


if __name__ == '__main__':
    main()
