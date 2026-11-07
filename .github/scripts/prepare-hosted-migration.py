#!/usr/bin/env python3
"""Prepare a fixed, source-bound normal migration journey on a disposable Mac."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

QUALIFIED_MAIN = 'PENDING_CURRENT_PUBLIC_ORCHESTRATION_INTAKE'
ROOT = Path('/Users/runner/work/_temp/mostlytext-focus')


def preparation():
    spec = importlib.util.spec_from_file_location('public_preparation', Path(__file__).with_name('prepare-hosted-public-focus.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def admit():
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before any migration access')
    if len(QUALIFIED_MAIN) != 40 or any(c not in '0123456789abcdef' for c in QUALIFIED_MAIN):
        raise RuntimeError('Migration execution is held pending qualified public orchestration intake')
    base = preparation()
    base.check_host(ROOT)
    subprocess.run(['git', 'merge-base', '--is-ancestor', QUALIFIED_MAIN, 'HEAD'], check=True, timeout=15)
    return base


def public_step(base, mode):
    saved = sys.argv[:]
    try:
        sys.argv = ['prepare-hosted-public-focus.py', str(ROOT)] + ([mode] if mode else [])
        base.main()
    finally:
        sys.argv = saved


def verify_seed(record, base):
    package = ROOT / 'seed'
    for name, digest in record['seed_generated_sha256'].items():
        if base.sha(package / name) != digest:
            raise RuntimeError('Generated migration seed input changed: ' + name)
    if record.get('seed_executable'):
        binary = Path(record['seed_executable'])
        if not binary.resolve().is_relative_to(package) or base.sha(binary) != record['seed_executable_sha256']:
            raise RuntimeError('Compiled migration seed changed')
    for name, digest in record.get('migration_compiled_sha256', {}).items():
        if base.sha(ROOT / name) != digest:
            raise RuntimeError('Compiled migration driver input changed: ' + name)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ['prepare', 'bind-built', 'bind-driver', 'verify']:
        raise RuntimeError('Select one fixed migration preparation phase')
    mode = sys.argv[1]
    base = admit()
    path = ROOT / 'receipt.json'
    if mode == 'prepare':
        public_step(base, '')
        record = json.loads(path.read_text())
        extra = base.output(['git', 'ls-files', '--', '.github/hosted-migration',
            '.github/scripts/prepare-hosted-migration.py', '.github/scripts/run-hosted-migration.py',
            '.github/scripts/migration_profile_evidence.py', '.github/scripts/test-hosted-migration.py',
            '.github/scripts/test-migration-seed-admission.py', '.github/workflows/hosted-migration.yml']).splitlines()
        required = {'.github/hosted-migration/' + p for p in ['Fixture/SeedAdmission.swift',
                    'Fixture/SeedProfile.swift', 'Fixture/Package.swift.in', 'Driver/MigrationTests.swift']}
        required.update('.github/scripts/' + p for p in ['prepare-hosted-migration.py', 'run-hosted-migration.py',
                        'migration_profile_evidence.py', 'test-hosted-migration.py', 'test-migration-seed-admission.py'])
        required.add('.github/workflows/hosted-migration.yml')
        if not required <= set(extra) or any(not Path(p).is_file() for p in extra):
            raise RuntimeError('Migration inputs are not all tracked')
        record['source_sha256'].update({p: base.sha(Path(p)) for p in extra})
        shutil.copyfile('.github/hosted-migration/Driver/MigrationTests.swift', ROOT / 'fixture/Driver/MigrationTests.swift')
        seed = ROOT / 'seed'
        shutil.copytree('.github/hosted-migration/Fixture', seed)
        template = (seed / 'Package.swift.in').read_text()
        if template.count('__BOUND_KIT_PATH__') != 1:
            raise RuntimeError('Invalid canonical package template')
        (seed / 'Package.swift').write_text(template.replace('__BOUND_KIT_PATH__', json.dumps(str(Path('MacDown2/Packages/MacDownKit').resolve()))))
        shutil.copyfile('MacDown2/Packages/MacDownKit/Package.resolved', seed / 'Package.resolved')
        record['seed_generated_sha256'] = {str(p.relative_to(seed)): base.sha(p) for p in seed.iterdir() if p.is_file()}
        record['migration_execution_started'] = False
        record['migration_qualified_main'] = QUALIFIED_MAIN
        path.write_text(json.dumps(record, indent=2) + '\n')
    else:
        record = json.loads(path.read_text())
        if record['migration_qualified_main'] != QUALIFIED_MAIN:
            raise RuntimeError('Migration receipt cannot be retargeted')
        verify_seed(record, base)
        public_step(base, '--bind-built' if mode == 'bind-built' else '--verify')
        if mode == 'bind-built':
            record = json.loads(path.read_text())
            binary = ROOT / 'seed/.build/release/SeedMigrationProfile'
            if not binary.resolve().is_relative_to(ROOT / 'seed') or not binary.is_file():
                raise RuntimeError('Missing private compiled seed')
            record.update(seed_executable=str(binary.resolve()), seed_executable_sha256=base.sha(binary))
            path.write_text(json.dumps(record, indent=2) + '\n')
        elif mode == 'bind-driver':
            if record.get('migration_compiled_sha256') or not record.get('seed_executable'):
                raise RuntimeError('Compiled migration fixture has already been bound or seed is absent')
            products = ROOT / 'control/Build/Products'
            files = [products / 'Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl']
            for pattern in ['*.xctestrun', 'Release/*-Runner.app/Contents/MacOS/*-Runner',
                            'Release/*-Runner.app/Contents/PlugIns/*.xctest/Contents/MacOS/HostedFocusDriverTests']:
                matching = list(products.glob(pattern))
                if len(matching) != 1:
                    raise RuntimeError('Ambiguous or missing actual compiled driver input: ' + pattern)
                files.extend(matching)
            record['migration_compiled_sha256'] = {str(p.relative_to(ROOT)): base.sha(p) for p in files}
            copies = ROOT / 'migration-compiled-inputs'
            copies.mkdir(mode=0o700)
            record['migration_compiled_downloads'] = {}
            for index, file in enumerate(files):
                target = copies / (str(index) + '-' + file.name)
                shutil.copyfile(file, target)
                record['migration_compiled_downloads'][str(target.relative_to(ROOT))] = base.sha(target)
            path.write_text(json.dumps(record, indent=2) + '\n')
        elif not record.get('seed_executable') or not record.get('migration_compiled_sha256'):
            raise RuntimeError('Migration seed/actual compiled driver has not been bound')


if __name__ == '__main__':
    main()
