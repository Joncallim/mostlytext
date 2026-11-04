#!/usr/bin/env python3
"""Check the recorded compiler image graph and selected files without executing it."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile

from verify_compiler_rt_notices import verify_installed as checked_notices

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/viz-compiler-image'
MANIFEST_SHA = '7df33ff8e62ab4bda297aa9fd2d89b65024b927ac7e968760e73289ba0a7f626'
INDEX_SHA = '4e332f7343b6f66320bf72f7ecc01a3d9f3866721a13b0e5c7b96505d6ab148a'
IMAGE_SHA = 'c2ac84c26ee40ae2f2c5a15bd3f9e608d1959e1b37413fa7f08138046a188dc5'
PREFIX = 'emsdk/upstream/emscripten/'
RELEASE_SHA = '63f302ebe7ed904608943bc13d2abe2653f9ccc444fe47046409b680db5614dc'
SDK_PATHS = {'emsdk/.emscripten', 'emsdk/emscripten-releases-tags.json', 'emsdk/emsdk_manifest.json'}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def checked_graph(raw_index, raw_image, raw_config):
    if sha(raw_index) != INDEX_SHA:
        raise ValueError('Publisher compiler index digest differs')
    index = json.loads(raw_index)
    children = [x for x in index['manifests'] if x['platform'] == {'architecture': 'amd64', 'os': 'linux'}]
    if len(children) != 1 or children[0]['digest'] != 'sha256:' + IMAGE_SHA:
        raise ValueError('Unique recorded AMD64 image required')
    if len(raw_image) != children[0]['size'] or sha(raw_image) != IMAGE_SHA:
        raise ValueError('AMD64 child manifest differs')
    image = json.loads(raw_image)
    if (sha(raw_config) != image['config']['digest'].removeprefix('sha256:')
            or len(raw_config) != image['config']['size']):
        raise ValueError('Image config digest/size differs')
    config = json.loads(raw_config)
    if (config['architecture'], config['os']) != ('amd64', 'linux'):
        raise ValueError('Image config platform differs')
    layers = image['layers']
    if (len(layers) != 4 or len(config['rootfs']['diff_ids']) != 4
            or len({x['digest'] for x in layers}) != 4
            or sum(x['size'] for x in layers) != 822423251):
        raise ValueError('Complete ordered four-layer image required')
    return index, image, config


def validate_layer_receipt(rows, image, config):
    if not isinstance(rows, list) or len(rows) != 4:
        raise ValueError('Complete layer verification receipt required')
    for number, (row, layer) in enumerate(zip(rows, image['layers'])):
        if (row.get('digest') != layer['digest'] or type(row.get('compressedBytes')) is not int
                or row['compressedBytes'] != layer['size']
                or row.get('uncompressedDigest') != config['rootfs']['diff_ids'][number]
                or type(row.get('uncompressedBytes')) is not int or row['uncompressedBytes'] <= 0):
            raise ValueError('Layer digest/order/size or uncompressed diff differs')


def read_selected(layers, wanted, maximum=4 * 1024 * 1024):
    """Read selected regular files with overlay whiteouts; never apply a rootfs."""
    final, events = {}, []
    for layer, archive in layers:
        seen = set()
        with tarfile.open(archive, 'r:gz') as stream:
            for member in stream:
                name = member.name
                while name.startswith('./'):
                    name = name[2:]
                name = name.rstrip('/')
                if not name:
                    continue
                if name.startswith('/') or any(x in ('', '.', '..') for x in name.split('/')):
                    raise ValueError('Unsafe image path')
                path = PurePosixPath(name)
                parent, leaf = str(path.parent), path.name
                if leaf == '.wh..wh..opq':
                    removed = [k for k in final if parent == '.' or k.startswith(parent + '/')]
                elif leaf.startswith('.wh.'):
                    target = str(path.parent / leaf[4:])
                    removed = [k for k in final if k == target or k.startswith(target + '/')]
                else:
                    ancestors = any(k.startswith(name + '/') for k in wanted)
                    if (name in wanted or ancestors) and (member.issym() or member.islnk()):
                        raise ValueError('Selected image path traverses a link')
                    if ancestors and not member.isdir():
                        raise ValueError('Selected image parent is not a directory')
                    if name not in wanted:
                        continue
                    if not member.isfile() or name in seen or member.size > maximum:
                        raise ValueError('Selected source must be bounded, unique and regular')
                    seen.add(name)
                    body = stream.extractfile(member).read()
                    if len(body) != member.size:
                        raise ValueError('Selected source read is incomplete')
                    final[name] = (body, layer)
                    continue
                for key in removed:
                    del final[key]
                if removed:
                    events.append({'layer': layer, 'marker': name, 'removed': removed})
    return final, events


def validate_selected(data, old, image):
    expected = {PREFIX + row['path'] for row in old['inputs']} | SDK_PATHS
    rows = data.get('files')
    if not isinstance(rows, list) or len(rows) != 9 or {r['path'] for r in rows} != expected:
        raise ValueError('Complete selected nine-file set required')
    records = {r['path']: r for r in rows}
    source_layer = image['layers'][1]['digest']
    if any(r.get('layer') != source_layer or type(r.get('bytes')) is not int or r['bytes'] <= 0
           or r.get('localFile') != r['path'].replace('/', '--') for r in rows):
        raise ValueError('Selected source layer/size/local identity differs')
    comparisons = data.get('comparison')
    if (not isinstance(comparisons, list) or len(comparisons) != 6
            or {r['path'] for r in comparisons} != {r['path'] for r in old['inputs']}):
        raise ValueError('Six original source-reference comparisons required')
    for original in old['inputs']:
        actual = records[PREFIX + original['path']]
        marker = original['path'] == 'emscripten-version.txt'
        expected_sha = RELEASE_SHA if marker else original['sha256']
        expected_size = 8 if marker else original['bytes']
        if actual['sha256'] != expected_sha or actual['bytes'] != expected_size:
            raise ValueError('Selected actual image source/text differs')
        match = next(r for r in comparisons if r['path'] == original['path'])
        if (match['previousReferenceSHA256'] != original['sha256'] or match['image'] != actual
                or match['matchesPreviousSource'] is not (not marker)):
            raise ValueError('Release marker difference must remain explicit')
    if data.get('whiteoutEvents') != []:
        raise ValueError('Captured selected-source overlay changed')
    return records


def verify_installed(root=ROOT, inputs=None):
    folder = root / PACKET
    try:
        raw = (folder / 'manifest.json').read_bytes()
    except FileNotFoundError as error:
        raise ValueError('Pinned compiler-image proof missing') from error
    if sha(raw) != MANIFEST_SHA:
        raise ValueError('Pinned compiler-image manifest changed')
    manifest = json.loads(raw)
    for name, h in manifest['files'].items():
        if '/' in name or name in ('.', '..') or sha((folder / name).read_bytes()) != h:
            raise ValueError('Pinned compiler-image evidence changed: ' + name)
    raw_graph = [(folder / name).read_bytes() for name in ('index.json', 'amd64-manifest.json', 'amd64-config.json')]
    _, image, config = checked_graph(*raw_graph)
    old = checked_notices(root)
    if old['publisher_compiler_image']['digest']['sha256'] != INDEX_SHA:
        raise ValueError('Image graph does not bind recorded publisher input')
    receipt = json.loads((folder / 'layer-verification.json').read_text())
    validate_layer_receipt(receipt, image, config)
    selected = json.loads((folder / 'selected-files.json').read_text())
    records = validate_selected(selected, old, image)
    if inputs is not None:
        for name, expected in zip(('index.json', 'amd64-manifest.json', 'amd64-config.json'), raw_graph):
            if (inputs / name).read_bytes() != expected:
                raise ValueError('Raw image graph replay differs')
        layers = []
        for number, row in enumerate(receipt):
            archive = inputs / (row['digest'].removeprefix('sha256:') + '.tar.gz')
            h, count = hashlib.sha256(), 0
            with archive.open('rb') as file:
                while block := file.read(1024 * 1024):
                    h.update(block)
                    count += len(block)
            if h.hexdigest() != row['digest'].removeprefix('sha256:') or count != row['compressedBytes']:
                raise ValueError('Raw compressed layer differs')
            h, count = hashlib.sha256(), 0
            with gzip.open(archive, 'rb') as file:
                while block := file.read(1024 * 1024):
                    h.update(block)
                    count += len(block)
            if 'sha256:' + h.hexdigest() != config['rootfs']['diff_ids'][number] or count != row['uncompressedBytes']:
                raise ValueError('Raw uncompressed layer differs')
            layers.append((row['digest'], archive))
        actual, events = read_selected(layers, set(records))
        if set(actual) != set(records) or events:
            raise ValueError('Raw selected-source overlay differs')
        for name, (body, layer) in actual.items():
            if sha(body) != records[name]['sha256'] or len(body) != records[name]['bytes'] or layer != records[name]['layer']:
                raise ValueError('Raw selected image source differs')
        if actual[PREFIX + 'emscripten-version.txt'][0] != b'"5.0.7"\n':
            raise ValueError('Actual release marker differs')
        sdk = json.loads(actual['emsdk/emscripten-releases-tags.json'][0])
        if sdk['releases']['5.0.7'] != '6cd98e86d7749ff98b82b7f2ae78eb4f01942788':
            raise ValueError('SDK release mapping differs')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    verify_installed(inputs=args.inputs)
    print('Recorded compiler-image graph and selected-source identity: passed')
