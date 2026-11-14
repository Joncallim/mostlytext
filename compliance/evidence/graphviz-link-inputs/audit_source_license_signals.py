#!/usr/bin/env python3
"""Index license signals in every pinned link-member source candidate."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import tarfile


ROOT = Path(__file__).resolve().parent
SOURCES = {
    'graphviz': ('graphviz-16.0.0.tar.gz', '36a1de1aaf5a2023b14f95170a5f8f0b12522d1c305b517fc261966597050749'),
    'expat': ('expat-2.8.4.tar.gz', 'b8ece2437692dad44d851c4532723390a5a330990007706be9c8d2b90d294f36'),
    'emscripten': ('emscripten-263db4cf.tar.gz', 'd34ff1cb0ab99f74c0aefd4641f7a514754f2f6218d540d135ef1cf8467b08ba'),
}
SIGNALS = ('Eclipse Public License', 'Common Public License', 'CPL',
           'GNU General Public', 'Apache License',
           'MIT License', 'public domain', 'Free Software Foundation', 'BSD',
           'University of Illinois', 'All rights reserved',
           'Permission is hereby granted')


def sha(body):
    return hashlib.sha256(body).hexdigest()


def audit(inputs, emscripten_source=None):
    index = json.loads((ROOT / 'source-candidates.json').read_text())
    if len(index['members']) != 489:
        raise ValueError('candidate member index changed')
    files = []
    for family, (name, expected) in SOURCES.items():
        archive = emscripten_source if family == 'emscripten' and emscripten_source is not None else inputs / name
        if sha(archive.read_bytes()) != expected:
            raise ValueError('source archive changed: ' + name)
        wanted = {candidate['path']: candidate['sha256'] for row in index['members']
                  if row['source_archive'].startswith(family + '-')
                  for candidate in row['basename_candidates']}
        found = {}
        with tarfile.open(archive, 'r:gz') as source:
            for member in source:
                path = member.name.split('/', 1)[1] if '/' in member.name else ''
                if path not in wanted:
                    continue
                if path in found or not member.isfile() or member.size > 4 * 1024 * 1024:
                    raise ValueError('duplicate/non-file/oversize candidate: ' + path)
                raw = source.extractfile(member).read()
                if sha(raw) != wanted[path]:
                    raise ValueError('candidate body changed: ' + path)
                header = raw[:16000].decode('utf-8', 'replace')
                spdx = sorted(set(re.findall(r'SPDX-License-Identifier:\s*([^\r\n*]+)', header)))
                copyrights = [line.strip(' /*\t')[:240] for line in header.splitlines()[:100]
                              if 'copyright' in line.lower()][:8]
                found[path] = {'family': family, 'path': path, 'sha256': wanted[path],
                               'spdx_header': spdx,
                               'header_signals': [term for term in SIGNALS if term.lower() in header.lower()],
                               'copyright_header_lines': copyrights}
        if set(found) != set(wanted):
            raise ValueError('candidate files missing from source archive: ' + family)
        files.extend(found.values())
    if len(files) != 616 or len({(f['family'], f['path']) for f in files}) != 616:
        raise ValueError('candidate file union changed')
    return {'schema': 1, 'scope': 'first 16 KiB license signals for each possible source file; not a term determination',
            'status': 'review-required',
            'source_archives': {family: {'name': name, 'sha256': digest}
                                for family, (name, digest) in SOURCES.items()},
            'candidate_members': 489, 'source_files': len(files),
            'families': dict(sorted(Counter(f['family'] for f in files).items())),
            'files': sorted(files, key=lambda f: (f['family'], f['path']))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--emscripten-source', type=Path,
                        help='Pinned Emscripten source archive when separate from --inputs')
    parser.add_argument('--output', type=Path, default=ROOT / 'file-license-signals.json')
    args = parser.parse_args()
    body = json.dumps(audit(args.inputs, args.emscripten_source), indent=2, sort_keys=True) + '\n'
    args.output.write_text(body)
    print(json.dumps({'source_files': 616, 'sha256': sha(body.encode())}, indent=2))


if __name__ == '__main__':
    main()
