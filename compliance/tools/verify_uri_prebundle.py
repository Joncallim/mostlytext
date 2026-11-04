#!/usr/bin/env python3
"""Verify a pinned full URI-package reproduction; never run upstream JS in CI."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from verify_parser_reproduction import verify_installed as checked_outer, VSCODE_ARCHIVE

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/uri-prebundle-reproduction'
SOURCE = 'edfdccd976efaf4bb8fdeca87e97c47257721729'
MANIFEST_SHA = '6cb6948d83655e59b2df8fd5097757c98fec99d3384145f761a2e1f413fd3055'
TOOLS = {'webpack': '5.94.0', 'webpack-cli': '5.1.4', 'typescript': '5.2.2',
         'ts-loader': '9.4.4', 'path-browserify': '1.0.1', 'node': 'v20.19.0',
         'yarn': '1.22.22', 'npm': '10.8.2'}
LIB_MEMBERS = {f'lib/umd/{name}.{suffix}' for name in ('charCode', 'index', 'platform', 'uri', 'utils')
               for suffix in ('js', 'd.ts')} | {'lib/umd/index.js.map', 'lib/esm/index.mjs', 'lib/esm/index.mjs.map'}
PAYLOAD_MEMBERS = {'package/' + name for name in LIB_MEMBERS} | {
    'package/LICENSE.md', 'package/README.md', 'package/SECURITY.md', 'package/package.json'}
PATH_SOURCE = 'f6d60f9e7cd83f65f947cda34ef846e82706c044d9a9fa7c5b69718b13b78e28'
PATH_LICENSE = 'a22b9d5763f574e5db347c30acc0b33eaf4846767c03d2e27d012e864e79a824'
WEBPACK_LICENSE = '9068a8782d2fb4c6e432cfa25334efa56f722822180570802bf86e71b6003b1e'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def digest(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def validate_comparison(data, matching=True):
    rows = data.get('members')
    if (type(data.get('comparedMembers')) is not int or data['comparedMembers'] != 13
            or not isinstance(rows, list) or len(rows) != 13
            or {r.get('member') for r in rows} != LIB_MEMBERS):
        raise ValueError('Complete 13-member compilation comparison required')
    different = []
    for row in rows:
        if (not digest(row.get('publishedSHA256')) or not digest(row.get('rebuiltSHA256'))
                or type(row.get('bytes')) is not int or row['bytes'] <= 0):
            raise ValueError('Invalid compiled-member hashes or size')
        same = row['publishedSHA256'] == row['rebuiltSHA256']
        if row.get('byteIdentical') is not same:
            raise ValueError('Compiled-member equality claim differs')
        if not same:
            different.append(row['member'])
    if (data.get('missing') != [] or data.get('different') != different
            or type(data.get('identicalMembers')) is not int
            or data['identicalMembers'] != 13 - len(different)):
        raise ValueError('Compilation comparison counts differ')
    if matching != (not different):
        raise ValueError('Compilation comparison has wrong success/refusal result')
    return rows


def validate_receipt(data):
    if (data.get('sourceCommit') != SOURCE or data.get('toolchain') != TOOLS
            or type(data.get('sourceFilesVerified')) is not int or data['sourceFilesVerified'] != 23
            or data.get('changedSourceFiles') != []):
        raise ValueError('Tagged source/toolchain identity changed')
    if (data.get('publishedArchiveSHA256') != VSCODE_ARCHIVE
            or data.get('rebuiltArchiveSHA256') != VSCODE_ARCHIVE
            or data.get('archiveByteIdentical') is not True):
        raise ValueError('Complete published archive does not reproduce')
    payload = data.get('payload', {})
    rows = payload.get('members')
    if (payload.get('sameMemberSet') is not True or not isinstance(rows, list)
            or len(rows) != 17 or {r.get('member') for r in rows} != PAYLOAD_MEMBERS
            or any(r.get('byteIdentical') is not True for r in rows)):
        raise ValueError('Complete 17-member package payload required')
    validate_comparison(data.get('compiled', {}))
    if data.get('inputHashes') != {'pathBrowserifySource': PATH_SOURCE,
                                  'pathBrowserifyLicense': PATH_LICENSE,
                                  'webpackLicense': WEBPACK_LICENSE}:
        raise ValueError('Nested source/license linkage changed')


def verify_installed(root=ROOT, replay=None):
    folder = root / PACKET
    try:
        raw = (folder / 'manifest.json').read_bytes()
    except FileNotFoundError as error:
        raise ValueError('Pinned URI reproduction proof missing') from error
    if sha(raw) != MANIFEST_SHA:
        raise ValueError('Pinned URI reproduction manifest changed')
    manifest = json.loads(raw)
    for name, h in manifest['files'].items():
        if '/' in name or name in ('.', '..') or sha((folder / name).read_bytes()) != h:
            raise ValueError('Pinned URI reproduction file changed: ' + name)
    proof = json.loads((folder / 'reproduction.json').read_text())
    validate_receipt(proof)
    index = json.loads((folder / 'tagged-source-hashes.json').read_text())
    if (len(index) != 23 or any(not digest(h) or name.startswith('/') or '..' in name.split('/')
                               for name, h in index.items())):
        raise ValueError('Complete tagged-source hash index required')
    links = json.loads((folder / 'source-map-links.json').read_text())
    expected_links = {(m, 'src/' + n + '.ts')
                      for m, names in [('lib/esm/index.mjs.map', ['platform', 'uri', 'utils']),
                                       ('lib/umd/index.js.map', ['platform', 'uri', 'utils', 'index'])]
                      for n in names}
    if (len(links) != 7 or {(r['map'], r['taggedFile']) for r in links} != expected_links
            or any(r.get('exactBytes') is not True or r.get('sha256') != index.get(r.get('taggedFile'))
                   for r in links)):
        raise ValueError('Tagged source must equal actual published map sources')
    control = json.loads((folder / 'source-mutation-control.json').read_text())
    if control.get('expectedRefusal') is not True:
        raise ValueError('Actual source-mutation refusal required')
    validate_comparison(control['comparison'], matching=False)
    validate_comparison(json.loads((folder / 'restored-source-proof.json').read_text()))
    portable = json.loads((folder / 'portable-reproduction.json').read_text())
    for k in ('sourceCommit', 'sourceFilesVerified', 'toolchain', 'publishedArchiveSHA256',
              'rebuiltArchiveSHA256', 'archiveByteIdentical'):
        if portable.get(k) != proof[k]:
            raise ValueError('Portable recipe does not reproduce the same archive')
    outer = checked_outer(root)
    if outer['vscodeUri']['archiveSHA256'] != proof['publishedArchiveSHA256']:
        raise ValueError('URI reproduction does not bind outer parser input')
    mapped = json.loads((root / 'compliance/evidence/mermaid-11.17.2/module-notice-map.json').read_text())
    path = next(p for p in mapped['packages'] if p['name'] == 'path-browserify')
    if (path['version'] != '1.0.1' or len(path['mapped_sources']) != 1
            or path['mapped_sources'][0]['sha256'] != PATH_SOURCE
            or path['mapped_sources'][0]['generated_references'] != 1222
            or path['package_license_texts'][0]['sha256'] != PATH_LICENSE):
        raise ValueError('Nested path input does not bind current shipped mapping')
    inventory = json.loads((root / 'compliance/inventory.json').read_text())
    row = next(r for r in inventory['components'] if r['id'] == 'webpack-parser-runtime')
    if sha((root / row['licence_texts'][0]['path']).read_bytes()) != WEBPACK_LICENSE:
        raise ValueError('Distributed full Webpack text differs')
    if replay is not None:
        source = replay / ('source/vscode-uri-' + SOURCE)
        if (sha((replay / 'source.tar.gz').read_bytes()) != manifest['sourceArchiveSHA256']
                or sha((replay / 'published.tgz').read_bytes()) != VSCODE_ARCHIVE
                or sha((replay / 'packed/vscode-uri-3.1.0.tgz').read_bytes()) != VSCODE_ARCHIVE
                or any(sha((source / name).read_bytes()) != h for name, h in index.items())):
            raise ValueError('Retained archive/source replay differs')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-dir', type=Path)
    args = parser.parse_args()
    verify_installed(replay=args.replay_dir)
    print('Complete tagged URI archive/prebundle reproduction: passed')
