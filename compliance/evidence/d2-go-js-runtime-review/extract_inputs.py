#!/usr/bin/env python3
"""Extract only the two digest-pinned Go runtime comparison inputs."""

import argparse
import hashlib
from pathlib import Path
import tarfile


INPUTS = (
    ('d2_source', '91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391',
     'd2-581c91096b62d644fb5168313142c836b7e68e74/d2js/js/wasm/wasm_exec.js',
     'd2-wasm_exec.js', '42c92bf26a564050862e648642f9dc529673fb257d8d96139122da317ac46274'),
    ('go_toolchain', '4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a',
     'go/lib/wasm/wasm_exec.js', 'go1.24.6-wasm_exec.js',
     '0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14'),
)


def sha(body):
    return hashlib.sha256(body).hexdigest()


def extract(source, archive_sha, member_name, member_sha):
    if sha(source.read_bytes()) != archive_sha:
        raise ValueError('source archive digest changed: ' + source.name)
    with tarfile.open(source, 'r:gz') as archive:
        member = archive.getmember(member_name)
        if not member.isfile() or member.size > 32768:
            raise ValueError('runtime input is not a bounded regular file')
        body = archive.extractfile(member).read()
    if sha(body) != member_sha:
        raise ValueError('runtime input digest changed: ' + member_name)
    return body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--d2-source', type=Path, required=True)
    parser.add_argument('--go-toolchain', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() and (not args.output.is_dir() or any(args.output.iterdir())):
        raise ValueError('output directory must be empty')
    extracted = [(output_name, extract(getattr(args, field), archive_sha, member_name, member_sha))
                 for field, archive_sha, member_name, output_name, member_sha in INPUTS]
    args.output.mkdir(parents=True, exist_ok=True)
    for output_name, body in extracted:
        with (args.output / output_name).open('xb') as destination:
            destination.write(body)
        print(output_name, len(body), sha(body))


if __name__ == '__main__':
    main()
