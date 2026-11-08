#!/usr/bin/env python3
"""Create deterministic, valid large-image fixtures outside the measured app."""
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import struct
import sys
import zlib


MIB = 1 << 20
SMALL_PNG = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==')
CASE_ORDER = (
    # Cover each budget family before approaching the riskier upper cases.
    'source8', 'single8', 'occ16384', 'repeat3', 'aggregate96', 'distinct128',
    'source24', 'single24', 'repeat5', 'aggregate128',
    'source32', 'single32', 'occ65536',
    'distinct512', 'occ65537refusal', 'repeat6refusal',
    'aggregateOverRefusal', 'distinct513refusal',
)
ASSET_SIZES = {'small': len(SMALL_PNG), 'a8': 8 * MIB, 'a24': 24 * MIB,
               **{f'{letter}32': 32 * MIB for letter in 'abcd'}, 'eSmall': len(SMALL_PNG) + 21,
               **{f'count{index:03d}': len(SMALL_PNG) + 24 for index in range(513)}}


def sha_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(MIB), b''):
            digest.update(block)
    return digest.hexdigest()


def append_chunk(stream, kind, keyword, filler_byte, filler_count):
    length = len(keyword) + filler_count
    stream.write(struct.pack('>I', length))
    stream.write(kind)
    stream.write(keyword)
    crc = zlib.crc32(kind + keyword)
    block = bytes([filler_byte]) * min(MIB, filler_count)
    left = filler_count
    while left:
        data = block[:min(len(block), left)]
        stream.write(data)
        crc = zlib.crc32(data, crc)
        left -= len(data)
    stream.write(struct.pack('>I', crc & 0xffffffff))


def make_png(path, target_bytes, seed):
    if target_bytes == len(SMALL_PNG) and seed == 0:
        path.write_bytes(SMALL_PNG)
        return
    keyword = b'Comment\0'
    filler_count = target_bytes - len(SMALL_PNG) - 12 - len(keyword)
    if filler_count < 1 or seed not in range(1, 6):
        raise ValueError('Invalid PNG fixture size or seed')
    with path.open('wb') as stream:
        stream.write(SMALL_PNG[:-12])
        append_chunk(stream, b'tEXt', keyword, ord('A') + seed, filler_count)
        stream.write(SMALL_PNG[-12:])
    if path.stat().st_size != target_bytes:
        raise ValueError('PNG fixture size changed')


def make_distinct_png(path, ordinal):
    if ordinal not in range(513):
        raise ValueError('Distinct fixture ordinal is outside the count ladder')
    content = b'Comment\0' + f'{ordinal:04d}'.encode('ascii')
    with path.open('wb') as stream:
        stream.write(SMALL_PNG[:-12])
        stream.write(struct.pack('>I', len(content)))
        stream.write(b'tEXt')
        stream.write(content)
        stream.write(struct.pack('>I', zlib.crc32(b'tEXt' + content) & 0xffffffff))
        stream.write(SMALL_PNG[-12:])
    if path.stat().st_size != ASSET_SIZES[f'count{ordinal:03d}']:
        raise ValueError('Distinct PNG fixture size changed')


def assert_png(path):
    with path.open('rb') as stream:
        if stream.read(8) != b'\x89PNG\r\n\x1a\n':
            raise ValueError('PNG signature changed')
        chunks = []
        while True:
            header = stream.read(8)
            if len(header) != 8:
                raise ValueError('PNG chunk is missing')
            length, kind = struct.unpack('>I4s', header)
            crc = zlib.crc32(kind)
            left = length
            while left:
                data = stream.read(min(MIB, left))
                if not data:
                    raise ValueError('PNG chunk is truncated')
                crc = zlib.crc32(data, crc)
                left -= len(data)
            actual = stream.read(4)
            if len(actual) != 4 or struct.unpack('>I', actual)[0] != crc & 0xffffffff:
                raise ValueError('PNG chunk CRC changed')
            chunks.append(kind.decode('ascii'))
            if kind == b'IEND':
                if stream.read(1):
                    raise ValueError('PNG has trailing data')
                break
    if chunks not in (['IHDR', 'IDAT', 'IEND'], ['IHDR', 'IDAT', 'tEXt', 'IEND']):
        raise ValueError('Unexpected PNG chunk sequence')


def write_source(path, target):
    prefix = b'# Budget ramp\n\n'
    if target < len(prefix):
        raise ValueError('Source target is too small')
    with path.open('wb') as stream:
        stream.write(prefix)
        left = target - len(prefix)
        # A near-cap source should not also test the 32 MiB derived HTML cap.
        # One whitespace line exercises source admission but renders compactly.
        block = b' ' * MIB
        while left:
            data = block[:min(left, len(block))]
            stream.write(data)
            left -= len(data)


def case_definition(name):
    if name.startswith('source'):
        return {'mode': 'source', 'source_bytes': int(name[6:]) * MIB,
                'assets': {}, 'occurrences': 0, 'refusal': False, 'refusal_kind': None}
    if name.startswith('single'):
        size = int(name[6:])
        return {'mode': 'html', 'assets': {'pixel.png': f'a{size}'},
                'occurrences': 1, 'refusal': False, 'refusal_kind': None}
    if name.startswith('occ'):
        count = 65537 if 'refusal' in name else int(name[3:])
        return {'mode': 'html', 'assets': {'pixel.png': 'small'},
                'occurrences': count, 'refusal': count > 65536,
                'refusal_kind': 'budget-exceeded' if count > 65536 else None}
    if name.startswith('repeat'):
        count = int(name[6])
        return {'mode': 'html', 'assets': {'pixel.png': 'a32'},
                'occurrences': count, 'refusal': count == 6,
                'refusal_kind': 'budget-exceeded' if count == 6 else None}
    if name.startswith('aggregate'):
        letters = 'abcd' if name != 'aggregate96' else 'abc'
        assets = {f'{letter}.png': f'{letter}32' for letter in letters}
        if name == 'aggregateOverRefusal':
            assets['e.png'] = 'eSmall'
        return {'mode': 'html', 'assets': assets, 'occurrences': len(assets),
                'refusal': name == 'aggregateOverRefusal',
                'refusal_kind': 'unresolved-resources' if name == 'aggregateOverRefusal' else None}
    if name.startswith('distinct'):
        count = 513 if 'refusal' in name else int(name[8:])
        return {'mode': 'html',
                'assets': {f'pixel{index:03d}.png': f'count{index:03d}' for index in range(count)},
                'occurrences': count, 'refusal': count == 513,
                'refusal_kind': 'unresolved-resources' if count == 513 else None}
    raise ValueError('Unknown fixed ramp case')


def create_fixtures(root):
    root.mkdir(parents=True, exist_ok=False)
    assets_root = root / 'assets'
    assets_root.mkdir()
    assets = {}
    for name, size in ASSET_SIZES.items():
        path = assets_root / (name + '.png')
        if name.startswith('count'):
            make_distinct_png(path, int(name[5:]))
        else:
            seed = 0 if name == 'small' else 5 if name == 'eSmall' else ord(name[0]) - ord('a') + 1
            make_png(path, size, seed)
        assert_png(path)
        assets[name] = {'bytes': size, 'sha256': sha_file(path)}
    cases_root = root / 'cases'
    cases_root.mkdir()
    cases = {}
    for name in CASE_ORDER:
        definition = case_definition(name)
        folder = cases_root / name
        folder.mkdir()
        source = folder / 'source.md'
        if definition['mode'] == 'source':
            write_source(source, definition['source_bytes'])
        else:
            source.write_text('# Budget ramp\n\n' + ''.join(
                f'![{index}]({filename})\n\n'
                for index, filename in enumerate(
                    [next(iter(definition['assets']))] * definition['occurrences']
                    if name.startswith(('single', 'occ', 'repeat'))
                    else definition['assets'], start=1)))
        for filename, key in definition['assets'].items():
            os.link(assets_root / (key + '.png'), folder / filename)
        definition['source_bytes'] = source.stat().st_size
        definition['source_sha256'] = sha_file(source)
        definition['resource_bytes'] = sum(assets[key]['bytes'] for key in definition['assets'].values())
        definition['asset_sha256'] = {filename: assets[key]['sha256']
                                      for filename, key in definition['assets'].items()}
        cases[name] = definition
        (folder / 'manifest.json').write_text(json.dumps(definition, indent=2, sort_keys=True) + '\n')
    manifest = {'schema': 1, 'case_order': CASE_ORDER, 'assets': assets, 'cases': cases}
    (root / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return manifest


def check_host(root):
    account = pwd.getpwuid(os.getuid())
    expected = Path(os.environ.get('RUNNER_TEMP', '')) / 'export-budget-ramp'
    if (sys.flags.optimize or root != expected or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or platform.machine() != 'arm64'
            or platform.mac_ver()[0].split('.')[0] != '26'
            or any(os.path.lexists(path) for path in
                   ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('Refuse export ramp fixture creation outside the owned runner')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: prepare-export-budget-ramp.py <runner-root>')
    root = Path(sys.argv[1])
    check_host(root)
    result = create_fixtures(root / 'fixtures')
    print('Prepared deterministic export ramp fixtures:', len(result['cases']))


if __name__ == '__main__':
    main()
