#!/usr/bin/env python3
"""Preserve the complete tracked Brotli tag, including JS export-ignored by GitHub tarballs."""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import tarfile


COMMIT = 'ed738e842d2fbdf2d6459e39267a633c4a9b2f5d'
TREE = '66d65f2a9bf3dec372ceda26358ccc78ac3decab'


def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args])


def snapshot(directory):
    if git(directory, 'rev-parse', 'HEAD').strip().decode() != COMMIT:
        raise ValueError('Brotli checkout is not the pinned tag commit')
    if git(directory, 'rev-parse', 'HEAD^{tree}').strip().decode() != TREE:
        raise ValueError('Brotli checkout tree changed')
    if git(directory, 'status', '--porcelain', '--untracked-files=no').strip():
        raise ValueError('Brotli checkout has tracked edits')
    paths = [p.decode() for p in git(directory, 'ls-files', '-z').split(b'\0') if p]
    if len(paths) != 367 or len(set(paths)) != len(paths):
        raise ValueError('Brotli tracked-file set changed')
    if sum(path.startswith('js/') for path in paths) != 18:
        raise ValueError('Brotli JavaScript file set changed')
    for required in ('LICENSE', 'js/decode.ts', 'js/decode.js', 'js/decode.min.js', 'js/package.json'):
        if required not in paths:
            raise ValueError(f'Brotli source missing {required}')
    files = {}
    for path in paths:
        pure = PurePosixPath(path)
        if pure.is_absolute() or '..' in pure.parts:
            raise ValueError('unsafe tracked path')
        target = directory / path
        metadata = target.lstat()
        if stat.S_ISREG(metadata.st_mode):
            body = target.read_bytes()
            if git(directory, 'show', f'HEAD:{path}') != body:
                raise ValueError(f'Brotli file differs from pinned Git object: {path}')
            files[path] = ('file', body)
        elif stat.S_ISLNK(metadata.st_mode):
            link = os.readlink(target)
            if link.encode() != git(directory, 'show', f'HEAD:{path}'):
                raise ValueError(f'Brotli link differs from pinned Git object: {path}')
            files[path] = ('link', link)
        else:
            raise ValueError(f'unsupported Brotli tracked entry: {path}')
    return files


def write_archive(destination, files):
    with destination.open('wb') as output, gzip.GzipFile(fileobj=output, mode='wb', mtime=0, filename='') as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.PAX_FORMAT) as archive:
            for path, (kind, body) in sorted(files.items()):
                member = tarfile.TarInfo('brotli-v1.1.0-git/' + path)
                member.mode, member.mtime, member.uid, member.gid = 0o644, 0, 0, 0
                member.uname = member.gname = ''
                if kind == 'link':
                    member.type = tarfile.SYMTYPE
                    member.linkname = body
                else:
                    member.size = len(body)
                    archive.addfile(member, io.BytesIO(body))
                    continue
                archive.addfile(member)
    with tarfile.open(destination, 'r:gz') as archive:
        found = {}
        for member in archive:
            path = member.name.removeprefix('brotli-v1.1.0-git/')
            found[path] = ('link', member.linkname) if member.issym() else ('file', archive.extractfile(member).read())
    if found != files:
        raise ValueError('Brotli source snapshot readback mismatch')
    raw = destination.read_bytes()
    return {'upstream': 'google/brotli', 'tag': 'v1.1.0', 'commit': COMMIT, 'tree': TREE,
            'tracked_files': len(files), 'javascript_files': sum(p.startswith('js/') for p in files),
            'archive_bytes': len(raw), 'archive_sha256': hashlib.sha256(raw).hexdigest(),
            'decode_min_sha256': hashlib.sha256(files['js/decode.min.js'][1]).hexdigest(),
            'decode_ts_sha256': hashlib.sha256(files['js/decode.ts'][1]).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('refusing to overwrite a source snapshot')
    print(json.dumps(write_archive(args.output, snapshot(args.checkout)), indent=2))


if __name__ == '__main__':
    main()
