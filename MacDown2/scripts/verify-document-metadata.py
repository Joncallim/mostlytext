#!/usr/bin/env python3
"""Validate compiled document declarations and documented embedded CLI paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat

RANKS = {'Owner', 'Default', 'Alternate', 'None'}
ROLES = {'Editor', 'Viewer', 'Shell', 'None'}
MARKDOWN_TYPES = {'net.daringfireball.markdown', 'public.markdown'}
HELPER = Path('Contents/MacOS/mostlytext-cli')
RESOURCES = Path('Contents/Resources/MacDownKit_CommandLineSupport.bundle')


def validate_info(info):
    if not isinstance(info, dict):
        raise ValueError('invalid property-list root')
    declarations = info.get('CFBundleDocumentTypes')
    if not isinstance(declarations, list) or not declarations:
        raise ValueError('missing document declarations')
    markdown = 0
    for declaration in declarations:
        if not isinstance(declaration, dict):
            raise ValueError('invalid document declaration')
        rank = declaration.get('LSHandlerRank', 'Default')
        role = declaration.get('CFBundleTypeRole')
        if not isinstance(rank, str) or rank not in RANKS or not isinstance(role, str) or role not in ROLES:
            raise ValueError('unsupported document handler rank or role')
        types = declaration.get('LSItemContentTypes')
        if not isinstance(types, list) or not types or not all(isinstance(item, str) and item for item in types):
            raise ValueError('missing supported document types')
        if rank == 'Owner' and any(not item.startswith('app.mostlytext.') for item in types):
            raise ValueError('ordinary document types must not claim Owner')
        if MARKDOWN_TYPES.intersection(types):
            markdown += 1
            if rank != 'Default' or declaration['CFBundleTypeRole'] != 'Editor':
                raise ValueError('Markdown must use the ordinary Default editor rank')
    if markdown != 1:
        raise ValueError('expected one Markdown declaration')
    return len(declarations)


def regular_executable(path):
    value = path.lstat()
    if not stat.S_ISREG(value.st_mode) or not value.st_mode & 0o111:
        raise ValueError('missing regular embedded executable')


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.digest()


def verify(app, guide=None, standalone=None):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    count = validate_info(info)
    if info.get('CFBundleIdentifier') != 'app.mostlytext.MostlyText' or info.get('CFBundleDisplayName') != 'MostlyText':
        raise ValueError('unexpected application identity')
    name = info.get('CFBundleExecutable')
    if not isinstance(name, str) or not name or Path(name).name != name or name in {'.', '..'}:
        raise ValueError('invalid application executable name')
    main = app / 'Contents/MacOS' / name
    helper = app / HELPER
    regular_executable(main)
    regular_executable(helper)
    if os.path.samefile(main, helper) or digest(main) == digest(helper):
        raise ValueError('embedded CLI aliases the application executable')
    resources = app / RESOURCES
    if resources.is_symlink() or not resources.is_dir():
        raise ValueError('embedded CLI resource bundle is missing')
    if standalone is not None:
        regular_executable(standalone)
        if digest(helper) != digest(standalone):
            raise ValueError('embedded CLI differs from the built public command')
    if guide is not None:
        paths = re.findall(r'\$APP_BUNDLE/([^"\n]+)', guide.read_text())
        if not paths or any(Path(path) != HELPER for path in paths):
            raise ValueError('guide examples do not address the actual embedded CLI')
    return {'status': 'passed', 'document_declarations': count, 'embedded_helper': str(HELPER)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--guide', type=Path)
    parser.add_argument('--standalone-cli', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.app, args.guide, args.standalone_cli), sort_keys=True))


if __name__ == '__main__':
    main()
