#!/usr/bin/env python3
"""Rebuild the tagged upstream package in an owned directory; never publish it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

PACKET = Path(__file__).resolve().parent
SOURCE = 'edfdccd976efaf4bb8fdeca87e97c47257721729'
ARCHIVE = 'c6ec752d7a4858237389b23fb4d5ac05c2f1f606071cd212a9b54730e43cfc54'
TOOLS = {'webpack': '5.94.0', 'webpack-cli': '5.1.4', 'typescript': '5.2.2',
         'ts-loader': '9.4.4', 'path-browserify': '1.0.1'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(source, published, node, yarn, output):
    inputs = json.loads((PACKET / 'tagged-source-hashes.json').read_text())
    def check_sources():
        if any(sha(source / name) != digest for name, digest in inputs.items()):
            raise ValueError('Tagged source or original build input changed')
    check_sources()
    if sha(published) != ARCHIVE:
        raise ValueError('Published archive identity changed')
    node_version = subprocess.check_output([str(node), '--version'], text=True).strip()
    yarn_version = subprocess.check_output([str(node), str(yarn), '--version'], text=True).strip()
    if (node_version, yarn_version) != ('v20.19.0', '1.22.22'):
        raise ValueError('Use the recorded integrity-verified Node/Yarn toolchain')
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['PATH'] = str(node.parent) + os.pathsep + env.get('PATH', '')
    env['npm_config_ignore_scripts'] = 'true'
    def execute(name, args):
        with (output / (name + '.log')).open('w') as log:
            subprocess.run(args, cwd=source, env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
    execute('install', [str(node), str(yarn), '--no-default-rc', 'install',
                       '--frozen-lockfile', '--ignore-scripts', '--non-interactive',
                       '--cache-folder', str(output / 'yarn-cache')])
    versions = {name: json.loads((source / 'node_modules' / name / 'package.json').read_text())['version']
                for name in TOOLS}
    if versions != TOOLS:
        raise ValueError('Frozen build resolution differs')
    execute('compile', [str(node), 'node_modules/typescript/bin/tsc', '-p', './src'])
    execute('production', [str(node), 'node_modules/webpack-cli/bin/cli.js', '--mode=production'])
    packed = output / 'packed'
    packed.mkdir(exist_ok=True)
    npm = node.parent.parent / 'lib/node_modules/npm/bin/npm-cli.js'
    execute('pack', [str(node), str(npm), 'pack', '--ignore-scripts', '--json',
                     '--pack-destination', str(packed)])
    rebuilt = packed / 'vscode-uri-3.1.0.tgz'
    check_sources()
    receipt = {'sourceCommit': SOURCE, 'sourceFilesVerified': len(inputs),
               'toolchain': dict(versions, node=node_version, yarn=yarn_version,
                                 npm=subprocess.check_output([str(node), str(npm), '--version'], text=True).strip()),
               'publishedArchiveSHA256': sha(published), 'rebuiltArchiveSHA256': sha(rebuilt),
               'archiveByteIdentical': published.read_bytes() == rebuilt.read_bytes()}
    (output / 'portable-reproduction.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    if not receipt['archiveByteIdentical']:
        raise ValueError('Complete published archive does not reproduce')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'published', 'node', 'yarn', 'output'):
        parser.add_argument('--' + name, required=True, type=lambda value: Path(value).resolve())
    args = parser.parse_args()
    result = run(args.source, args.published, args.node, args.yarn, args.output)
    print('Complete vscode-uri 3.1.0 archive reproduced:', result['rebuiltArchiveSHA256'])
