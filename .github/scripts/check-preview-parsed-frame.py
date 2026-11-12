#!/usr/bin/env python3
"""Prove one actual mounted Markdown mutation fails and exact restoration passes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from preview_compiled_inputs import capture as capture_compiled, check_host, verify_execution


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('configuration', choices=['Debug', 'Release'])
    parser.add_argument('--pair', choices=['revision', 'viewport', 'disappear'], required=True)
    args = parser.parse_args()
    if os.environ.get('CI') != 'true':
        parser.error('Only the owned hosted app products may execute')
    check_host(args.output.resolve())
    repo = Path(__file__).resolve().parents[2]
    source = repo / 'MacDown2/MacDown2/SecuredMarkdownResourceHost.swift'
    original = source.read_bytes()
    needle = b'revision = document.revision'
    if original.count(needle) != 1:
        raise SystemExit('The revision-omission mutation requires exact reviewed source')
    replacement = b'revision = 0'
    content_needle = b'content(loader, current?.loadID)'
    if original.count(content_needle) != 1:
        raise SystemExit('The viewport mutation requires the exact stable host')
    replaced_container = (b'ZStack(alignment: .topLeading) {\n'
                          b'    content(loader, current?.loadID).id(current?.loadID)\n'
                          b'}.id(currentIdentity)')
    if original.count(b'let retiringContext = slot?.context') != 1:
        raise SystemExit('The disappearance mutation requires the exact stored-context retirement')
    experiments = [
        ('revision-mutant', original.replace(needle, replacement), 'SecuredMarkdownMountedTests', 4,
         'Mounted Textual did not admit the expected document-bound image'),
        ('revision-restored', original, 'SecuredMarkdownMountedTests', 4, None),
        ('viewport-mutant', original.replace(content_needle, replaced_container), 'SecuredMarkdownViewportTests', 1,
         'Resource replacement must retain the native scroll container'),
        ('viewport-restored', original, 'SecuredMarkdownViewportTests', 1, None),
        ('disappear-mutant', original.replace(b'let retiringContext = slot?.context',
                                             b'let retiringContext = current?.context'), 'SecuredMarkdownMountedTests', 4,
         'A hidden Preview must revoke its previous parsed-frame loader'),
        ('disappear-restored', original, 'SecuredMarkdownMountedTests', 4, None),
    ]
    experiments = [row for row in experiments if row[0].startswith(args.pair + '-')]
    if len(experiments) != 2:
        raise SystemExit('Exactly one mutation and its restoration must be selected')
    derived = Path(os.environ['RUNNER_TEMP']) / 'preview-grant-app'
    app = derived / 'Build/Products' / args.configuration / 'MacDown2.app/Contents/MacOS/MacDown2'
    base = ['xcodebuild', '-project', 'MacDown2/MacDown2.xcodeproj', '-scheme', 'MacDown2',
            '-configuration', args.configuration, 'ENABLE_TESTABILITY=YES',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RELEASE_PREVIEW_PROBE',
            '-destination', 'platform=macOS,arch=arm64', 'ONLY_ACTIVE_ARCH=YES', '-derivedDataPath', str(derived),
            '-onlyUsePackageVersionsFromResolvedFile', '-enableCodeCoverage', 'NO']
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    original_app = digest(app)
    try:
        for phase, candidate, suite, count, diagnostic in experiments:
            source.write_bytes(candidate)
            with (args.output / ('parsed-frame-' + phase + '-compile.log')).open('w') as log:
                subprocess.run(base + ['build-for-testing'], cwd=repo, check=True, timeout=900,
                               stdout=log, stderr=subprocess.STDOUT)
            app_digest = digest(app)
            if phase.endswith('mutant') and app_digest == original_app:
                raise SystemExit('The omission did not change the actual application executable')
            if phase.endswith('restored') and app_digest != original_app:
                raise SystemExit('The restored application differs from the unmodified executable')
            capture_compiled(args.output, derived / 'Build/Products', args.configuration,
                             repo / 'MacDown2/MacDown2.xcodeproj', phase)
            path = args.output / ('parsed-frame-' + phase + '.log')
            with path.open('w') as log:
                result = subprocess.run([
                    sys.executable, str(repo / '.github/scripts/run-owned-app-tests.py'),
                    str(args.output / ('parsed-frame-' + phase + '-diagnostics')), str(app), '--',
                ] + base + ['-parallel-testing-enabled', 'NO',
                            '-resultBundlePath', str(args.output / ('actual-' + phase + '.xcresult')),
                            '-only-testing:MacDown2Tests/' + suite, 'test-without-building'],
                    cwd=repo, timeout=660, stdout=log, stderr=subprocess.STDOUT)
            verify_execution(args.output, args.configuration, phase)
            records.append({'phase': phase, 'returncode': result.returncode,
                            'source_sha256': digest(source), 'app_sha256': app_digest,
                            'original_app_sha256': original_app})
            (args.output / 'parsed-frame-results.json').write_text(json.dumps(records, indent=2) + '\n')
            log = re.sub(r'\x1b\[[0-9;]*m', '', path.read_text())
            summary = 'Test run with ' + str(count) + (' test' if count == 1 else ' tests') + ' in 1 suite '
            if diagnostic is not None:
                if result.returncode == 0 or diagnostic not in log:
                    raise SystemExit('The actual counterfactual did not fail its intended assertion: ' + phase)
                if not re.search(re.escape(summary) + 'failed', log):
                    raise SystemExit('The complete counterfactual selection did not execute')
                unaffected = {
                    'revision-mutant': ['aNoWriteNativeCopyCannotReuseAnEarlierImage',
                                        'aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration',
                                        'hidingDuringAParsedFrameReplacementRevokesTheRetainedLoader'],
                    'disappear-mutant': ['aNoWriteNativeCopyCannotReuseAnEarlierImage',
                                         'aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration',
                                         'aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit'],
                }.get(phase, [])
                for function in unaffected:
                    if not re.search(r'Test ' + re.escape(function) + r'\(\) passed', log):
                        raise SystemExit('An unaffected mounted positive control also failed: ' + function)
            elif result.returncode != 0 or not re.search(re.escape(summary) + 'passed', log):
                raise SystemExit('The exact restored native controls did not pass: ' + phase)
    finally:
        source.write_bytes(original)
        if source.read_bytes() != original:
            raise SystemExit('Failed to restore exact parsed-frame source')
    print('Actual ' + args.pair + ' counterfactual fails; exact restored application passes all selected controls')


if __name__ == '__main__':
    main()
