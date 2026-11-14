#!/usr/bin/env python3
"""Wrap a TrueType sfnt as deterministic WOFF1 without changing table bytes.

This intentionally supports only ordinary TrueType inputs. It does not subset,
rename, normalize metadata, or synthesize a new sfnt. Verification compares every
decompressed WOFF table and its checksum with the original directory.
"""

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path

TTF_HEADER = struct.Struct('>IHHHH')
TTF_ENTRY = struct.Struct('>4sIII')
WOFF_HEADER = struct.Struct('>4sIIHHIHHIIIII')
WOFF_ENTRY = struct.Struct('>4sIIII')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def convert(ttf):
    if len(ttf) < TTF_HEADER.size:
        raise ValueError('truncated sfnt')
    flavor, count, search_range, entry_selector, range_shift = TTF_HEADER.unpack_from(ttf)
    if flavor != 0x00010000 or not 1 <= count <= 128:
        raise ValueError('only bounded TrueType sfnt is supported')
    entries = []
    names = set()
    for i in range(count):
        tag, checksum, offset, length = TTF_ENTRY.unpack_from(ttf, TTF_HEADER.size + TTF_ENTRY.size * i)
        if tag in names or offset + length > len(ttf):
            raise ValueError('duplicate or out-of-range table')
        names.add(tag)
        entries.append((tag, checksum, ttf[offset:offset + length]))
    data_offset = WOFF_HEADER.size + count * WOFF_ENTRY.size
    directory = bytearray()
    payload = bytearray()
    report = []
    for tag, checksum, raw in entries:
        packed = zlib.compress(raw, 9)
        if len(packed) >= len(raw):
            packed = raw
        offset = data_offset + len(payload)
        directory += WOFF_ENTRY.pack(tag, offset, len(packed), len(raw), checksum)
        payload += packed
        payload += b'\0' * (-len(payload) % 4)
        report.append({'tag': tag.decode('ascii'), 'sha256': sha(raw), 'length': len(raw), 'checksum': f'{checksum:08x}'})
    total_sfnt_size = 12 + count * 16 + sum((len(raw) + 3) // 4 * 4 for _, _, raw in entries)
    header = WOFF_HEADER.pack(b'wOFF', flavor, data_offset + len(payload), count, 0,
                              total_sfnt_size, 2, 0, 0, 0, 0, 0, 0)
    woff = header + directory + payload
    for i, (_, _, raw) in enumerate(entries):
        tag, off, packed_size, raw_size, _ = WOFF_ENTRY.unpack_from(woff, WOFF_HEADER.size + i * WOFF_ENTRY.size)
        unpacked = woff[off:off + packed_size]
        if packed_size < raw_size:
            unpacked = zlib.decompress(unpacked)
        if unpacked != raw:
            raise AssertionError(f'{tag!r}: table changed')
    return woff, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ttf', type=Path, required=True)
    parser.add_argument('--woff', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    ttf = args.ttf.read_bytes()
    woff, tables = convert(ttf)
    args.woff.write_bytes(woff)
    args.report.write_text(json.dumps({'input_sha256': sha(ttf), 'output_sha256': sha(woff),
                                       'converter': 'Python 3 stdlib zlib.compress level 9, WOFF1; no metadata block',
                                       'table_count': len(tables), 'tables': tables}, indent=2) + '\n')


if __name__ == '__main__':
    main()
