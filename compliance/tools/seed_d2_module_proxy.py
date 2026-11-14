#!/usr/bin/env python3
"""Build an offline file GOPROXY from a verified D2 source-review archive."""

import argparse
import hashlib
import io
import json
import tarfile
import zipfile
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_new(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() and any(args.output.iterdir()):
        raise ValueError('output proxy must be empty')
    args.output.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.archive, 'r:gz') as source:
        members = source.getmembers()
        if any(not m.isfile() or m.name.startswith('/') or '..' in Path(m.name).parts for m in members):
            raise ValueError('unsafe source-review member')
        names = [m.name for m in members]
        if len(names) != len(set(names)):
            raise ValueError('duplicate source-review member')
        manifest = json.load(source.extractfile('manifest.json'))
        for row in manifest['files']:
            body = source.extractfile(row['path']).read()
            if len(body) != row['size'] or sha(body) != row['sha256']:
                raise ValueError('source-review manifest mismatch')
        rows = []
        for number in range(1, 17):
            entry = f'original-review/modules/{number:02}/source.zip'
            body = source.extractfile(entry).read()
            with zipfile.ZipFile(io.BytesIO(body)) as module_zip:
                files = module_zip.namelist()
                roots = {name.split('@', 1)[0] + '@' + name.split('@', 1)[1].split('/', 1)[0]
                         for name in files if '@' in name}
                if len(roots) != 1:
                    raise ValueError(f'{entry}: unexpected ZIP root')
                root = roots.pop()
                module, version = root.rsplit('@', 1)
                if any(name.startswith('/') or '..' in Path(name).parts or not name.startswith(root + '/')
                       for name in files):
                    raise ValueError(f'{entry}: unsafe ZIP path')
                mod_path = root + '/go.mod'
                mod = module_zip.read(mod_path) if mod_path in files else f'module {module}\n'.encode()
            escaped = ''.join('!' + char.lower() if char.isupper() else char for char in module)
            target = args.output / escaped / '@v'
            write_new(target / f'{version}.zip', body)
            write_new(target / f'{version}.mod', mod)
            write_new(target / f'{version}.info', (json.dumps({'Version': version}) + '\n').encode())
            rows.append({'module': module, 'version': version, 'zip_sha256': sha(body),
                         'mod_sha256': sha(mod)})
    print(json.dumps({'source_archive_sha256': sha(args.archive.read_bytes()),
                      'module_count': len(rows), 'modules': rows}, indent=2))


if __name__ == '__main__':
    main()
