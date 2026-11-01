#!/usr/bin/env python3
"""Compile SDK witnesses only. Never launch or register an application/extension."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.absolute()
output.mkdir(parents=True, exist_ok=False)
source = Path(__file__).resolve().with_name('APICompileOnlyProvider.swift')
sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
negative = output / 'InheritedMethod.swift'
negative.write_text(source.read_text().replace(
    'APICompileOnlyProvider: QLPreviewProvider, QLPreviewingController',
    'InheritedMethod: QLPreviewProvider'
).replace('    func providePreview', '    override func providePreview'))
base = ['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete',
        '-warnings-as-errors', '-sdk', str(sdk)]
rows = []
for name, command in [
    ('inherited-method-negative', base + ['-typecheck', str(negative)]),
    ('explicit-protocol-positive', base + ['-typecheck', str(source)]),
    ('library-compile', base + ['-emit-library', '-parse-as-library', str(source),
                              '-o', str(output / 'libQuickLookAPIWitness.dylib')]),
]:
    result = subprocess.run(command, capture_output=True, text=True)
    text = result.stdout + result.stderr
    (output / (name + '.log')).write_text(text)
    rows.append({'name': name, 'command': command, 'exit': result.returncode})
    if name == 'inherited-method-negative':
        assert result.returncode != 0 and 'does not override any method' in text
    else:
        assert result.returncode == 0, text
headers = sdk / 'System/Library/Frameworks/QuickLookUI.framework/Headers'
record = {
    'timeUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'sdk': str(sdk),
    'headerSHA256': {name: hashlib.sha256((headers / name).read_bytes()).hexdigest()
                     for name in ['QLPreviewProvider.h', 'QLPreviewingController.h', 'QLPreviewReply.h']},
    'steps': rows,
    'librarySHA256': hashlib.sha256((output / 'libQuickLookAPIWitness.dylib').read_bytes()).hexdigest(),
    'applicationLaunched': False,
    'extensionPackagedOrRegistered': False,
    'runtimeAcceptance': 'NOT_RUN',
}
(output / 'validation.json').write_text(json.dumps(record, indent=2) + '\n')
print('SDK API controls pass: required conformance and reply/attachment library compile; runtime NOT_RUN')
