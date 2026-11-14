#!/usr/bin/env python3
"""Index every possible link-stage archive member without claiming final retention."""

import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PIN = '520b112060cd872b775da8b41d5ae2775b6d590128c9b3cd6110049ad1a57877'


def main():
    data = (ROOT / 'result.json').read_bytes()
    if hashlib.sha256(data).hexdigest() != PIN:
        raise ValueError('link-stage receipt changed')
    index = json.loads(data)['index']
    mapped = set(index['map_archive_members'])
    extracted = set(index['extracted_archive_members'])
    if len(mapped) != 426 or len(extracted) != 457 or len(mapped | extracted) != 489:
        raise ValueError('unexpected link-stage member set')
    entries = []
    for identity in sorted(mapped | extracted):
        match = re.fullmatch(r'(.*/)?([^/]+\.a)\(([^()]+)\)', identity)
        if not match:
            raise ValueError(f'unknown archive/member syntax: {identity}')
        archive, member = match.group(2, 3)
        family = ('graphviz' if archive.startswith(('libgv', 'libcgraph', 'libcdt', 'libpathplan', 'libxdot'))
                  else 'expat' if archive == 'libexpat.a'
                  else 'compiler-rt' if archive == 'libcompiler_rt.a'
                  else 'libc++' if archive == 'libc++-noexcept.a'
                  else 'libc++abi' if archive == 'libc++abi-noexcept.a'
                  else 'emscripten-sysroot')
        entries.append({'archive': archive, 'member': member,
                        'mapped': identity in mapped, 'extracted': identity in extracted,
                        'source_family': family,
                        'per_file_terms': 'review-required'})
    out = {'schema': 1, 'scope': 'union of pre-optimization wasm-ld map and extraction; conservative candidate input index',
           'receipt_sha256': PIN, 'mapped': len(mapped), 'extracted': len(extracted),
           'union': len(entries), 'by_family': dict(sorted(Counter(e['source_family'] for e in entries).items())),
           'members': entries}
    (ROOT / 'union-review.json').write_text(json.dumps(out, indent=2) + '\n')


if __name__ == '__main__':
    main()
