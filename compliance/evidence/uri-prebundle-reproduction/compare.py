#!/usr/bin/env python3
"""Compare every published lib member with an owned upstream build; execute no JS."""
import argparse
import hashlib
import json
from pathlib import Path


def compare(published: Path, rebuilt: Path) -> dict:
    members = sorted(path.relative_to(published).as_posix()
                     for path in (published / 'lib').rglob('*') if path.is_file())
    if not members:
        raise ValueError('Published lib member set is empty')
    rows = []
    for name in members:
        a = (published / name).read_bytes()
        target = rebuilt / name
        b = target.read_bytes() if target.is_file() else None
        rows.append({'member': name, 'bytes': len(a),
                     'publishedSHA256': hashlib.sha256(a).hexdigest(),
                     'rebuiltSHA256': hashlib.sha256(b).hexdigest() if b is not None else None,
                     'byteIdentical': a == b})
    return {'comparedMembers': len(rows), 'identicalMembers': sum(r['byteIdentical'] for r in rows),
            'missing': [r['member'] for r in rows if r['rebuiltSHA256'] is None],
            'different': [r['member'] for r in rows if not r['byteIdentical']], 'members': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--published', required=True, type=Path)
    parser.add_argument('--rebuilt', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = compare(args.published, args.rebuilt)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(f"Compared {result['comparedMembers']} published members: {result['identicalMembers']} identical")
    raise SystemExit(1 if result['different'] else 0)
