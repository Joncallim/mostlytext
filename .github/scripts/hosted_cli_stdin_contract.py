"""Private source/compiled/result contracts; importing never executes native code."""
import hashlib
import json
import os
from pathlib import Path
import stat

MAX_BYTES = 256 * 1024 * 1024


def read_regular(path):
    path = Path(path)
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > MAX_BYTES:
        raise RuntimeError('Linked, special or oversized evidence input')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as handle:
        opened = os.fstat(handle.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_nlink) != (before.st_dev, before.st_ino, 1):
            raise RuntimeError('Evidence identity changed before reading')
        raw = handle.read(MAX_BYTES + 1)
    after = path.lstat()
    stamp = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns)
    if stamp(before) != stamp(after) or len(raw) != before.st_size:
        raise RuntimeError('Evidence changed while reading')
    return raw


def sha(path):
    return hashlib.sha256(read_regular(path)).hexdigest()


def capture(root, paths):
    root = Path(root)
    target = root / 'cli-compiled.json'
    if target.exists():
        raise RuntimeError('The compiled source has already been sealed')
    folder = root / 'cli-compiled'
    folder.mkdir(mode=0o700)
    rows = {}
    for role, source in paths.items():
        source = Path(source)
        if source.resolve() != source or not source.is_relative_to(root):
            raise RuntimeError('Compiled input is outside the owned physical root')
        raw = read_regular(source)
        digest = hashlib.sha256(raw).hexdigest()
        blob = folder / digest
        if blob.exists():
            if read_regular(blob) != raw:
                raise RuntimeError('Previously captured bytes changed')
        else:
            with blob.open('xb') as output:
                output.write(raw)
        rows[role] = {'path': str(source), 'bytes': len(raw), 'sha256': digest,
                      'blob': str(blob.relative_to(root))}
    with target.open('x') as output:
        output.write(json.dumps(rows, indent=2) + '\n')
    return rows


def verify(root, paths):
    root = Path(root)
    rows = json.loads(read_regular(root / 'cli-compiled.json'))
    if set(rows) != set(paths):
        raise RuntimeError('Compiled roles were omitted or retargeted')
    for role, source in paths.items():
        row = rows[role]
        if row['path'] != str(source) or row['blob'] != 'cli-compiled/' + row['sha256']:
            raise RuntimeError('Compiled path or archive was retargeted')
        for path in [Path(source), root / row['blob']]:
            raw = read_regular(path)
            if len(raw) != row['bytes'] or hashlib.sha256(raw).hexdigest() != row['sha256']:
                raise RuntimeError('Compiled bytes changed: ' + role)
    return rows


def require_ui(summary, owned, code):
    expected = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0,
                'skippedTests': 0, 'expectedFailures': 0}
    if any(type(summary.get(key)) is not int or summary[key] != value for key, value in expected.items()):
        raise RuntimeError('The complete selected native case did not pass')
    if (type(code) is not int or code != 0 or type(owned.get('returncode')) is not int or owned['returncode'] != 0
            or owned.get('timed_out') is not False or owned.get('cancelled') is not False
            or owned.get('app_cleanup_requested') != []):
        raise RuntimeError('The actual owned native selection did not finish normally')
