#!/usr/bin/env python3
"""Fetch only the recorded public image blobs, verify them, and never run an image."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from verify_viz_image import INDEX_SHA, IMAGE_SHA, checked_graph, verify_installed

BASE = 'https://registry-1.docker.io/v2/emscripten/emsdk'


def capture(output):
    output.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen('https://auth.docker.io/token?service=registry.docker.io&scope=repository:emscripten/emsdk:pull', timeout=30) as response:
        token = json.load(response)['token']
    def request(path):
        return urllib.request.urlopen(urllib.request.Request(BASE + path, headers={
            'Authorization': 'Bearer ' + token,
            'Accept': 'application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'}), timeout=60)
    def metadata(path, digest, name):
        with request(path) as response:
            body = response.read()
        if hashlib.sha256(body).hexdigest() != digest:
            raise ValueError('Registry metadata digest differs')
        target = output / name
        if target.exists() and target.read_bytes() != body:
            raise ValueError('Refuse to replace differing retained metadata')
        target.write_bytes(body)
        return body
    index = metadata('/manifests/sha256:' + INDEX_SHA, INDEX_SHA, 'index.json')
    image = metadata('/manifests/sha256:' + IMAGE_SHA, IMAGE_SHA, 'amd64-manifest.json')
    descriptor = json.loads(image)['config']
    config = metadata('/blobs/' + descriptor['digest'], descriptor['digest'].removeprefix('sha256:'), 'amd64-config.json')
    _, manifest, _ = checked_graph(index, image, config)
    for layer in manifest['layers']:
        name = layer['digest'].removeprefix('sha256:')
        target = output / (name + '.tar.gz')
        if not target.exists():
            partial = output / (name + '.partial')
            count, digest = 0, hashlib.sha256()
            with request('/blobs/' + layer['digest']) as response, partial.open('wb') as file:
                while block := response.read(1024 * 1024):
                    count += len(block)
                    if count > layer['size']:
                        raise ValueError('Registry blob exceeds recorded bound')
                    digest.update(block)
                    file.write(block)
            if count != layer['size'] or digest.hexdigest() != name:
                raise ValueError('Registry blob digest/size differs')
            partial.rename(target)
        print('Retained recorded layer:', name, flush=True)
    # This hashes both compressed and uncompressed bytes and reads only selected
    # source records; it does not extract/apply a rootfs or execute its contents.
    verify_installed(inputs=output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=lambda value: Path(value).resolve())
    capture(parser.parse_args().output)
    print('Recorded compiler image captured and verified without execution')
