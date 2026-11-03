#!/usr/bin/env python3
"""Preserve selected Go source comments without claiming exact binary retention."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

from audit_d2_source import read_json_stream
from audit_d2_go_runtime import GO_SHA

SELECTION_SHA = '0aa0c071a6fd8dcc4e200cf21bcdd2f25b53dcb6a00d63afc3d2cf9ac63b352c'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def selection(graph):
    rows = []
    packages = 0
    for package in read_json_stream(graph):
        if package.get('Error'):
            raise ValueError('Go graph contains a package error')
        if package.get('Standard') is not True:
            continue
        packages += 1
        import_path = package['ImportPath']
        expected = '/go/src/' + import_path
        if not package['Dir'].endswith(expected):
            raise ValueError('Go directory/import identity mismatch')
        for kind in ['GoFiles', 'SFiles', 'CgoFiles']:
            for name in package.get(kind, []):
                if '/' in name or name in ['.', '..']:
                    raise ValueError('unsafe selected source name')
                rows.append({'path': 'go/src/' + import_path + '/' + name, 'package': import_path})
    rows.sort(key=lambda row: row['path'])
    canonical = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()
    if packages != 192 or len(rows) != 1013 or len({row['path'] for row in rows}) != len(rows) or sha(canonical) != SELECTION_SHA:
        raise ValueError('standard-library source selection changed')
    return rows


def fragments(path, body):
    lines = body.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    result = []

    def locate(predicate, start=0):
        index = next((i for i in range(start, len(lines)) if predicate(lines[i])), None)
        if index is None:
            raise ValueError('missing source notice boundary')
        return index

    def add(kind, start, end):
        text = body[offsets[start]:offsets[end]]
        result.append({'kind': kind, 'text': text.decode('utf-8'), 'sha256': sha(text),
                       'source': {'path': path, 'source_sha256': sha(body),
                                  'start_byte': offsets[start], 'end_byte': offsets[end]}})

    for index, line in enumerate(lines):
        if b'Copyright' in line and b'The Go Authors' in line:
            add('Go copyright', index, index + 1)
    if b'Sun Microsystems' in body:
        start = locate(lambda line: b'Copyright' in line and b'Sun Microsystems' in line)
        if start and b'====' in lines[start - 1]:
            start -= 1
        end = next((i + 1 for i in range(start + 2, len(lines)) if b'====' in lines[i]), None)
        if end is None or not all(token in b''.join(lines[start:end]) for token in [b'Permission to use, copy, modify, and distribute', b'provided that this notice', b'is preserved.']):
            raise ValueError('incomplete Sun notice')
        add('Sun source notice', start, end)
    if b'Stephen L. Moshier' in body:
        start = locate(lambda line: b'Cephes Math Library Release' in line)
        end = next((i + 1 for i in range(start, len(lines)) if b'moshier@' in lines[i]), None)
        if end is None or not all(token in b''.join(lines[start:end]) for token in [b'What you see here may be used freely', b'no support or', b'guarantee.']):
            raise ValueError('incomplete Cephes notice/readme excerpt')
        add('Cephes source notice', start, end)
    if b'fiat-crypto code comes under' in body:
        start = locate(lambda line: b'fiat-crypto code comes under' in line)
        end = next((i for i in range(start, len(lines)) if lines[i].startswith(b'// NewScalar returns')), None)
        if end is None or not all(token in b''.join(lines[start:end]) for token in [b'Redistributions of source code must retain', b'notice, this list of conditions', b'AS IS', b'POSSIBILITY OF SUCH DAMAGE']):
            raise ValueError('incomplete fiat-crypto notice')
        add('fiat-crypto source notice', start, end)
    return result


def render(groups, root_license, patents):
    parts = [
        'Go 1.24.6 selected standard-library source-build notices\n'
        'Conservative attribution to the frozen D2 publisher-source build graph.\n'
        'Selection does not prove every source file was emitted. These comments\n'
        'and original terms are preserved, not replaced by a new grant.\n\n',
        'Complete Go root license (also byte-identical in the four vendor roots):\n\n',
        root_license.decode(), '\nComplete Go additional IP rights grant:\n\n', patents.decode(), '\n',
    ]
    for group in sorted(groups, key=lambda group: (group['kind'], group['sha256'])):
        parts += ['\n' + group['kind'] + '\n', group['text']]
    return ''.join(parts).encode('utf-8')


def prepare(graph, archive):
    rows = selection(graph)
    if sha(archive.read_bytes()) != GO_SHA:
        raise ValueError('official Go archive digest mismatch')
    extra = ['go/LICENSE', 'go/PATENTS']
    extra += ['go/src/vendor/golang.org/x/' + module + '/LICENSE' for module in ['crypto', 'net', 'sys', 'text']]
    wanted = {row['path'] for row in rows} | set(extra)
    bodies = {}
    # Read the compressed archive once; repeated random seeks are expensive.
    with tarfile.open(archive, mode='r|gz') as source:
        for member in source:
            if member.name not in wanted:
                continue
            if member.name in bodies or not member.isfile() or member.size > 16 * 1024 * 1024:
                raise ValueError('duplicate/unsafe selected archive member')
            bodies[member.name] = source.extractfile(member).read()
    if set(bodies) != wanted:
        raise ValueError('missing selected compiler source/license input')
    for name in extra[2:]:
        if bodies[name] != bodies['go/LICENSE']:
            raise ValueError('vendor license differs from root; independent disposition required')
    by_digest = {}
    candidate_files = set()
    for row in rows:
        body = bodies[row['path']]
        row['sha256'] = sha(body)
        for fragment in fragments(row['path'], body):
            if fragment['kind'] != 'Go copyright':
                candidate_files.add(row['path'])
            key = (fragment['kind'], fragment['sha256'])
            group = by_digest.setdefault(key, {k: fragment[k] for k in ['kind', 'text', 'sha256']})
            group.setdefault('sources', []).append(fragment['source'])
    if len(candidate_files) != 21:
        raise ValueError('supplemental source notice count changed')
    groups = list(by_digest.values())
    notice = render(groups, bodies['go/LICENSE'], bodies['go/PATENTS'])
    report = {'schema': 1, 'go_version': 'go1.24.6', 'go_archive_sha256': GO_SHA,
              'selection_sha256': SELECTION_SHA, 'captured_go_list_sha256': sha(graph.read_bytes()),
              'standard_packages': 192, 'selected_files': rows,
              'root_texts': [{'path': name, 'sha256': sha(bodies[name]), 'text': bodies[name].decode()} for name in extra[:2]],
              'vendor_root_licenses': extra[2:], 'supplemental_source_files': len(candidate_files),
              'fragments': groups, 'notice_sha256': sha(notice),
              'limits': 'Conservative publisher-source-build attribution, not exact file emission, original-grant clearance, complete runtime/source audit or approval/publication.'}
    return report, notice


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['go-list', 'go-archive', 'manifest', 'notice']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    report, notice = prepare(args.go_list, args.go_archive)
    args.manifest.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    args.notice.write_bytes(notice)


if __name__ == '__main__':
    main()
