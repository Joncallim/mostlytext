"""Bounded, no-link filesystem and typed domain evidence for fictional profiles."""
import hashlib
import json
import os
from pathlib import Path
import stat
from urllib.parse import unquote, urlparse


def sha(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(root, archive):
    root, archive = Path(root), Path(archive)
    if root.is_symlink() or root.resolve() != root:
        raise RuntimeError('Profile root is not a physical path')
    archive.mkdir(mode=0o700, parents=True, exist_ok=False)
    rows = {}
    total = 0
    if not root.exists():
        return rows
    pending = [root]
    while pending:
        path = pending.pop()
        info = path.lstat()
        name = str(path.relative_to(root))
        if len(rows) >= 2048:
            raise RuntimeError('Profile entry bound exceeded')
        row = {'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid,
               'gid': info.st_gid, 'inode': info.st_ino, 'device': info.st_dev}
        if stat.S_ISDIR(info.st_mode):
            row['kind'] = 'directory'
            pending.extend(sorted(path.iterdir(), reverse=True))
        elif stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
            if info.st_size > 16 * 1024 * 1024:
                raise RuntimeError('Profile file bound exceeded')
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, 'rb') as handle:
                opened = os.fstat(handle.fileno())
                if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino) or opened.st_nlink != 1:
                    raise RuntimeError('Profile identity changed before read')
                data = handle.read(16 * 1024 * 1024 + 1)
            after = path.lstat()
            if (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != (
                    after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
                raise RuntimeError('Profile changed during read')
            total += len(data)
            if len(data) != info.st_size or total > 64 * 1024 * 1024:
                raise RuntimeError('Profile byte bound exceeded')
            row.update(kind='file', size=len(data), sha256=sha(data))
            target = archive / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            target.write_bytes(data)
        else:
            raise RuntimeError('Profile link or special node refused: ' + name)
        rows[name] = row
    return rows


def require_preserved(original, preserved):
    if set(original) != set(preserved):
        raise RuntimeError('Preserved profile inventory differs')
    for name, row in original.items():
        other = preserved[name]
        if any(row.get(k) != other.get(k) for k in ['kind', 'size', 'sha256']):
            raise RuntimeError('Preserved profile bytes differ: ' + name)
        if other['uid'] != row['uid'] or other['mode'] & 0o077:
            raise RuntimeError('Preserved profile ownership/permissions differ: ' + name)


def editor_width(domain):
    value = domain['appSettings.editor']
    if not isinstance(value, bytes):
        raise RuntimeError('Canonical editor preference must be encoded Data')
    editor = json.loads(value)
    width = editor['indentationWidth']
    if type(width) is not int:
        raise RuntimeError('Invalid indentation width')
    return width


def require_blocked_preservation(baseline, after, seed, external_bytes, sentinel_exists):
    if after['trees']['old'] != baseline['trees']['old'] or after['domains'] != baseline['domains']:
        raise RuntimeError('Blocked startup changed original profile or persistent domains')
    if after['trees']['state'] or any(
            name == 'installation-v1' or name.startswith('installation-v1/') or name in {
                'installation-preferences.json', 'installation-paths.json', 'installation-complete.json'}
            for name in after['trees']['installation']):
        raise RuntimeError('Blocked startup published authoritative installation state')
    if sentinel_exists or sha(external_bytes) != seed['externalSHA256']:
        raise RuntimeError('Blocked startup executed a command or changed external authored bytes')


def require_session(seed, session, state):
    expected = seed['session']
    if session['version'] != expected['version'] or len(session['tabs']) != 2:
        raise RuntimeError('Unexpected migrated session inventory')
    if session['activeTabID'] != expected['activeTabID']:
        raise RuntimeError('Managed active tab identity changed')
    for before, after in zip(expected['tabs'], session['tabs']):
        for key in ['id', 'documentRecoveryEpoch', 'baseSHA256', 'encoding']:
            if before.get(key) != after.get(key):
                raise RuntimeError('Session identity/encoding changed: ' + key)
        parsed = urlparse(after['fileURL'])
        if parsed.scheme != 'file' or parsed.netloc not in ['', 'localhost']:
            raise RuntimeError('Nonlocal restored file URL')
        actual = Path(unquote(parsed.path))
        source = Path(unquote(urlparse(before['fileURL']).path))
        wanted = Path(state) / source.relative_to(seed['old']) if source.is_relative_to(seed['old']) else source
        if actual != wanted:
            raise RuntimeError('Managed path relocation differs')
