#!/usr/bin/env python3
"""Compare exact D2 WOFF tables to a published Liberation Mono reference.

Only the two pinned inputs are admitted. This is technical correspondence, not
proof of original conversion provenance, functional equivalence or RFN clearance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import tarfile
import zlib

from verify_d2_font import WOFF_SHA

ARCHIVE_SHA = 'f14ff0a0be87b5aeb672e669363b5a699db76feb1144b06798261c0fdcd2b24d'
TTF_SHA = '816a2a46416a2d3550b401ff8d0c084ba7e8138782f7057b1e537446012f769a'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def compare(woff_path, reference_path):
    woff = woff_path.read_bytes()
    if sha(woff) != WOFF_SHA:
        raise ValueError('D2 font digest changed before parsing')
    if sha(reference_path.read_bytes()) != ARCHIVE_SHA:
        raise ValueError('Publisher font reference archive changed before parsing')
    with tarfile.open(reference_path) as archive:
        matches = [m for m in archive.getmembers() if m.isfile() and m.name.endswith('/LiberationMono-Regular.ttf')]
        if len(matches) != 1:
            raise ValueError('Expected one regular reference TTF member')
        reference_member = matches[0].name
        ttf = archive.extractfile(matches[0]).read()
    if sha(ttf) != TTF_SHA:
        raise ValueError('Publisher TTF member differs')
    # Parsing occurs only after exact complete input identity has been checked;
    # this is not an arbitrary-font inspection API or unbounded input admission.
    woff_tables = {}
    for index in range(struct.unpack_from('>H', woff, 12)[0]):
        tag, offset, compressed, original, _ = struct.unpack_from('>4sIIII', woff, 44 + index * 20)
        body = woff[offset:offset + compressed]
        if compressed < original:
            body = zlib.decompress(body)
        if len(body) != original or tag in woff_tables:
            raise ValueError('WOFF table length or identity differs')
        woff_tables[tag] = body
    ttf_tables = {}
    for index in range(struct.unpack_from('>H', ttf, 4)[0]):
        tag, _, offset, length = struct.unpack_from('>4sIII', ttf, 12 + index * 16)
        body = ttf[offset:offset + length]
        if len(body) != length or tag in ttf_tables:
            raise ValueError('TTF table length or identity differs')
        ttf_tables[tag] = body
    rows = []
    for tag in sorted(woff_tables.keys() | ttf_tables.keys()):
        a, b = woff_tables.get(tag), ttf_tables.get(tag)
        rows.append({'table': tag.decode('ascii'), 'woff_bytes': len(a) if a is not None else None,
                     'ttf_bytes': len(b) if b is not None else None,
                     'woff_sha256': sha(a) if a is not None else None,
                     'reference_ttf_sha256': sha(b) if b is not None else None,
                     'identical': a == b,
                     'differing_byte_offsets': [i for i, pair in enumerate(zip(a, b)) if pair[0] != pair[1]]
                     if a is not None and b is not None else None})
    def post(body):
        return {'underline_position': struct.unpack_from('>h', body, 8)[0],
                'underline_thickness': struct.unpack_from('>h', body, 10)[0],
                'is_fixed_pitch': struct.unpack_from('>I', body, 12)[0]}
    return {'schema': 1, 'scope': 'Technical reference comparison; not RFN legal clearance, functional-equivalence finding or exact conversion-origin proof',
            'reference_release': '2.00.5', 'reference_tag_commit': '24ea9469bfb089ab9bf05adb0871d0065d360edc',
            'reference_archive_sha256': ARCHIVE_SHA, 'reference_member': reference_member,
            'reference_ttf_sha256': TTF_SHA, 'woff_sha256': WOFF_SHA,
            'table_count': len(rows), 'identical_tables': sum(row['identical'] for row in rows),
            'tables': rows, 'post_metadata': {'d2_woff': post(woff_tables[b'post']),
                                            'publisher_ttf': post(ttf_tables[b'post'])},
            'name_table_identical': woff_tables[b'name'] == ttf_tables[b'name'],
            'font_or_name_changed_by_this_audit': False, 'strict_release_gate_cleared': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--woff', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.woff, args.reference)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'table_count': result['table_count'], 'identical_tables': result['identical_tables'],
                      'post_metadata': result['post_metadata'], 'strict_release_gate_cleared': False}, indent=2))


if __name__ == '__main__':
    main()
