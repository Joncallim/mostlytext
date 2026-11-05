#!/usr/bin/env python3
"""Prepare the hashed Foundation-only fixture; never execute native products."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine-repo', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
packet = Path(__file__).resolve().parent
repo = packet.parents[3]
rows = json.loads((packet / 'source-files.json').read_text())
prepared = []
for row in rows:
    if row['owner'] == 'namespace':
        data = row['contents'].encode()
    elif row['owner'] == 'engine':
        data = subprocess.check_output(['git', '-C', str(args.engine_repo), 'show', row['revision'] + ':' + row['path']])
    else:
        data = (repo / row['path']).read_bytes()
    if hashlib.sha256(data).hexdigest() != row['sha256']:
        raise SystemExit('Exact source mismatch: ' + row['fixture'])
    prepared.append((row['fixture'], data))
args.output.mkdir(parents=True, exist_ok=False)
for relative, data in prepared:
    target = args.output / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
manifest = (packet / 'fixture-Package.swift').read_text().replace(
    json.dumps('__REPO__/MacDown2/Packages/MathSyntax'), json.dumps(str(repo / 'MacDown2/Packages/MathSyntax')))
(args.output / 'Package.swift').write_text(manifest)
(args.output / 'Package.resolved').write_bytes((packet / 'fixture-Package.resolved').read_bytes())
print(f'Prepared {len(rows)} hash-verified files. Execution is separate: swift test --package-path OUTPUT --force-resolved-versions')
