#!/usr/bin/env python3
"""Bind D2's reviewed ELK JavaScript history receipt to the pinned source archive."""

import argparse
import hashlib
import json
import tarfile
from pathlib import Path

ARCHIVE_SHA256 = '91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391'
MEMBER = ('d2-581c91096b62d644fb5168313142c836b7e68e74/'
          'd2layouts/d2elklayout/elk.js')
MEMBER_SHA256 = 'a297b92da4a257b95c129cc1d8cfb379e2c89bcd4442af90ac06fdd2b1e220b4'
MEMBER_GIT_BLOB_SHA1 = '9ea3a05eb3e8e9663a9b2022e911940a19de264f'


def sha256(body):
    return hashlib.sha256(body).hexdigest()


def verify(archive_path, receipt_path):
    receipt = json.loads(receipt_path.read_text())
    if receipt['schema'] != 1 or receipt['d2_source_archive_sha256'] != ARCHIVE_SHA256:
        raise ValueError('D2 source receipt identity changed')
    if sha256(archive_path.read_bytes()) != ARCHIVE_SHA256:
        raise ValueError('D2 source archive digest changed')
    with tarfile.open(archive_path, 'r:gz') as archive:
        member = archive.getmember(MEMBER)
        if not member.isfile() or member.size != receipt['member_bytes'] or member.size > 4_000_000:
            raise ValueError('D2 ELK source member is not the expected bounded file')
        body = archive.extractfile(member).read()
    git_blob = b'blob ' + str(len(body)).encode() + b'\0' + body
    if (receipt['member_path'] != MEMBER or len(body) != receipt['member_bytes']
            or sha256(body) != MEMBER_SHA256
            or receipt['member_sha256'] != MEMBER_SHA256
            or hashlib.sha1(git_blob).hexdigest() != MEMBER_GIT_BLOB_SHA1
            or receipt['member_git_blob_sha1'] != MEMBER_GIT_BLOB_SHA1
            or receipt['history'][-1]['file_blob_sha1'] != MEMBER_GIT_BLOB_SHA1):
        raise ValueError('D2 ELK source does not match the recorded Git history tip')
    return len(body), MEMBER_SHA256, MEMBER_GIT_BLOB_SHA1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--receipt', type=Path,
                        default=Path(__file__).with_name('history.json'))
    args = parser.parse_args()
    size, digest, blob = verify(args.archive, args.receipt)
    print(f'ELK_SOURCE_MATCH: {size} bytes; SHA-256 {digest}; Git blob {blob}')


if __name__ == '__main__':
    main()
