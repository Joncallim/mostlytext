#!/usr/bin/env python3
"""Check first-party compiler-extracted keys against their owned catalogs.

Consumes Xcode stringsdata from a complete current build. It does not compile
or run the application, assess translation quality, or discover plain Strings
that never entered the compiler's localization pipeline.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


class CoverageError(ValueError):
    pass


# This SwiftPM executable is a test-only process probe, not an app/CLI Xcode
# compilation input. Pin its exact source so adding a localization key (or any
# other code) requires an explicit review of this exemption.
NON_SHIPPING_SOURCE_EXEMPTIONS = {
    Path('MacDown2/Packages/MacDownKit/Sources/QuickLookSourceProbe/main.swift'):
        '12764f69a3627d273d77bdc2483c264522c4e2e55ab275f61c792254a192c1f7',
}


def source_roots(repo: Path) -> list[Path]:
    return [repo / path for path in (
        'MacDown2/MacDown2', 'MacDown2/MacDown2CLI',
        'MacDown2/Packages/MacDownKit/Sources',
    )]


def expected_sources(repo: Path) -> set[Path]:
    expected = {path.resolve() for root in source_roots(repo) for path in root.rglob('*.swift')
                if 'Resources' not in path.relative_to(root).parts}
    for relative, approved_sha256 in NON_SHIPPING_SOURCE_EXEMPTIONS.items():
        source = (repo / relative).resolve()
        if source not in expected:
            continue
        if hashlib.sha256(source.read_bytes()).hexdigest() != approved_sha256:
            raise CoverageError(f'non-shipping compiler exemption changed: {relative}')
        expected.remove(source)
    return expected


def catalog_for(repo: Path, source: Path) -> Path | None:
    relative = source.relative_to(repo)
    if relative.parts[:2] == ('MacDown2', 'MacDown2'):
        return repo / 'MacDown2/MacDown2/Localizable.xcstrings'
    if relative.parts[:4] == ('MacDown2', 'Packages', 'MacDownKit', 'Sources'):
        return repo / Path(*relative.parts[:5]) / 'Resources/Localizable.xcstrings'
    return None


def check(repo: Path, extraction: Path, configuration: str | None = None) -> dict:
    repo = repo.resolve(strict=True)
    expected = expected_sources(repo)
    if not expected:
        raise CoverageError('no owned Swift compilation inputs found')
    records: dict[Path, tuple] = {}
    routes: set[tuple[str, str, str, int]] = set()
    catalogs: dict[Path, dict] = {}
    for path in sorted(extraction.rglob('*.stringsdata')):
        if configuration is not None and configuration not in path.relative_to(extraction).parts[:-1]:
            continue
        data = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data, dict) or not isinstance(data.get('source'), str):
            raise CoverageError(f'{path.name}: missing compiler source identity')
        source = Path(data['source'])
        source = (source if source.is_absolute() else repo / source).resolve()
        # External dependencies and generated accessors are not first-party UI.
        owned = any(source.is_relative_to(root) for root in source_roots(repo))
        if not owned or 'Resources' in source.relative_to(repo).parts:
            continue
        if source not in expected or not source.is_file():
            raise CoverageError(f'unknown or missing owned source: {source.relative_to(repo)}')
        tables = data.get('tables')
        if type(data.get('version')) is not int or data['version'] != 1 or not isinstance(tables, dict):
            raise CoverageError(f'{source.name}: malformed compiler record')
        normalized = []
        for table, entries in tables.items():
            if table != 'Localizable' or not isinstance(entries, list):
                raise CoverageError(f'{source.name}: unknown table or malformed entries')
            for entry in entries:
                if not isinstance(entry, dict) or not isinstance(entry.get('key'), str):
                    raise CoverageError(f'{source.name}: malformed compiler key')
                location = entry.get('location')
                line = location.get('startingLine') if isinstance(location, dict) else None
                if type(line) is not int or not 1 <= line <= len(source.read_text().splitlines()):
                    raise CoverageError(f'{source.name}: malformed compiler location')
                normalized.append((table, entry['key'], line))
        identity = tuple(sorted(normalized))
        if source in records and records[source] != identity:
            raise CoverageError(f'{source.name}: inconsistent architecture extraction')
        records[source] = identity
        if not identity:
            continue
        catalog = catalog_for(repo, source)
        if catalog is None or not catalog.is_file():
            raise CoverageError(f'{source.name}: no owned string catalog')
        if catalog not in catalogs:
            content = json.loads(catalog.read_text(encoding='utf-8'))
            if not isinstance(content, dict) or not isinstance(content.get('strings'), dict):
                raise CoverageError(f'{catalog.name}: malformed catalog')
            catalogs[catalog] = content['strings']
        for _, key, line in identity:
            routes.add((catalog.relative_to(repo).as_posix(), key,
                        source.relative_to(repo).as_posix(), line))
    missing_sources = expected - records.keys()
    if missing_sources:
        names = ', '.join(path.relative_to(repo).as_posix() for path in sorted(missing_sources))
        raise CoverageError(f'incomplete compiler extraction: {names}')
    if not routes:
        raise CoverageError('complete extraction contains no owned localized keys')
    rows = [{'catalog': catalog, 'key': key, 'source': source, 'line': line}
            for catalog, key, source, line in sorted(routes)]
    missing = [row for row in rows if row['key'] not in catalogs[repo / row['catalog']]]
    return {
        'schema': 1, 'status': 'missing-keys' if missing else 'passed',
        'configuration': configuration,
        'compiled_sources': len(records), 'catalogs': len(catalogs),
        'distinct_keys': len({(row['catalog'], row['key']) for row in rows}),
        'routes': rows, 'missing': missing,
        'source_sha256': {source.relative_to(repo).as_posix(): hashlib.sha256(source.read_bytes()).hexdigest()
                          for source in sorted(records)},
        'scope': 'Current-build compiler/catalog coverage only; not plain-String discovery, translation quality or native/final-freeze acceptance.',
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--extraction-dir', type=Path, required=True)
    parser.add_argument('--configuration', default='Release', help='exact Xcode configuration directory (default: Release)')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = check(args.repo, args.extraction_dir, args.configuration)
    except (CoverageError, OSError, ValueError, TypeError) as error:
        print(json.dumps({'status': 'invalid', 'error': str(error)}))
        return 1
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ('status', 'compiled_sources', 'catalogs', 'distinct_keys')}
                     | {'missing_routes': len(result['missing'])}))
    return int(bool(result['missing']))


if __name__ == '__main__':
    raise SystemExit(main())
