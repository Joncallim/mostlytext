#!/usr/bin/env python3
"""Independently bind the hosted C comparison receipt to immutable Git inputs."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path('/Volumes/Fast SSD/CORTANA-Builds/parser-runtime-compilation-20261107')
ART = ROOT / 'local-combined-c-qualification'
APP = Path('/Volumes/Fast SSD/CORTANA-GitHub/worktrees/github/mostlytext-shared-subtree-comparison')
RUNTIME = Path('/Volumes/Fast SSD/CORTANA-GitHub/tree-sitter-unified-compilation')
GRAMMAR = Path('/Volumes/Fast SSD/CORTANA-Builds/shared-subtree-comparison-20261106/application-build/checkouts/tree-sitter-json')
HEAD = '39d0de72b9cf554d9add4cb92ea1cc6583f564f3'
BASE = 'd607098bdb5046c02d81137b497e0ffe1aa01748'

def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])

def blob(repo, revision, path):
    return git(repo, 'show', revision + ':' + path)

def sha(data):
    return hashlib.sha256(data).hexdigest()

receipt = json.loads((ART / 'receipt.json').read_text())
checkout = receipt['checkout']
source_tree = git(APP, 'rev-parse', HEAD + '^{tree}').decode().strip()
assert checkout == HEAD
assert git(APP, 'rev-parse', checkout + '^{tree}').decode().strip() == source_tree
assert git(APP, 'merge-tree', '--write-tree', BASE, HEAD).decode().strip() == source_tree
paths = git(APP, 'ls-tree', '-r', '--name-only', HEAD, '--', 'MacDown2',
            '.github/scripts/run-shared-subtree-comparison-probe.py',
            '.github/scripts/test-shared-subtree-pin-review.py',
            '.github/workflows/shared-subtree-comparison.yml', 'compliance/inventory.json',
            'compliance/licenses/tree-sitter--LICENSE.txt').decode().splitlines()
assert set(paths) == set(receipt['source_sha256'])
# Read every blob through one Git process, independently of the workflow recorder.
raw = subprocess.check_output(['git', '-C', str(APP), 'cat-file', '--batch'],
                              input=''.join(HEAD + ':' + p + '\n' for p in paths).encode())
offset = 0
for path in paths:
    end = raw.index(b'\n', offset)
    header = raw[offset:end].split()
    assert header[1] == b'blob'
    size = int(header[2])
    data = raw[end + 1:end + 1 + size]
    assert sha(data) == receipt['source_sha256'][path], path
    offset = end + 1 + size + 1
assert offset == len(raw)
lock = json.loads(blob(APP, HEAD, 'MacDown2/Packages/MacDownKit/Package.resolved'))
assert receipt['pins'] == lock['pins'] and len(lock['pins']) == 24
pins = {p['identity']: p for p in lock['pins']}
assert len(pins) == 24
runtime = pins['tree-sitter']['state']['revision']
grammar = pins['tree-sitter-json']['state']['revision']
original = '5ce80b6f0e29096a5f06826a3ba610c4e89bc255'
assert receipt['runtime_original'] == original
assert receipt['runtime_candidate'] == runtime == '3b1fb00f8c4f8907073f9b7342a807a0231867fa'
assert receipt['grammar_revision'] == grammar == 'ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24'
assert pins['tree-sitter']['location'] == 'https://github.com/Joncallim/tree-sitter'
assert pins['tree-sitter-json']['location'] == 'https://github.com/tree-sitter/tree-sitter-json'
assert sha(blob(RUNTIME, runtime, 'lib/tests/subtree_compare_identity.c')) == receipt['fixture_sha256']
assert receipt['runtime_product_delta'] == ['Package.swift', 'lib/src/subtree.c']
assert git(RUNTIME, 'diff', '--name-only', original, runtime, '--',
           'lib/src', 'lib/include', 'Package.swift').decode().splitlines() == ['Package.swift', 'lib/src/subtree.c']
for phase, revision in [('original', original), ('candidate', runtime)]:
    assert sha(blob(RUNTIME, revision, 'lib/src/subtree.c')) == receipt['runtime_subtree_sha256'][phase]
    assert blob(RUNTIME, revision, 'LICENSE') == blob(APP, HEAD, 'compliance/licenses/tree-sitter--LICENSE.txt')
for phase, revision in [('original', original), ('candidate', runtime)]:
    assert sha(blob(RUNTIME, revision, 'Package.swift')) == receipt['runtime_manifest_sha256'][phase]
    cpaths = git(RUNTIME, 'ls-tree', '-r', '--name-only', revision, '--', 'lib/src').decode().splitlines()
    cpaths = [n for n in cpaths if n.endswith('.c') and n != 'lib/src/lib.c']
    assert len(cpaths) == 13
    observed = receipt['effective_runtime_c_sha256'][phase]
    assert set(observed) == {n[len('lib/'):] for n in cpaths}
    for path in cpaths:
        assert sha(blob(RUNTIME, revision, path)) == observed[path[len('lib/'):]]
grammar_paths = git(GRAMMAR, 'ls-tree', '-r', '--name-only', grammar, '--', 'src').decode().splitlines()
assert set(grammar_paths) == set(receipt['grammar_source_sha256'])
for path in grammar_paths:
    assert sha(blob(GRAMMAR, grammar, path)) == receipt['grammar_source_sha256'][path]

phases = ['original', 'candidate', 'original-work', 'candidate-work', 'candidate-sanitized']
assert [r['phase'] for r in receipt['results']] == phases
expected_output = (ART / 'original.log').read_bytes()
expected_pairs = [l for l in expected_output.splitlines() if l.startswith(b'compare ')]
assert len(expected_pairs) == 324
assert len(set((int(l.split()[1]), int(l.split()[2])) for l in expected_pairs)) == 324
for phase, result in zip(phases, receipt['results']):
    expected = 2 if phase == 'original-work' else 0
    status = json.loads((ART / (phase + '.log.status.json')).read_text())
    compile_status = json.loads((ART / (phase + '-compile.log.status.json')).read_text())
    assert compile_status['returncode'] == compile_status['expected'] == 0
    assert status['returncode'] == status['expected'] == result['returncode'] == expected
    assert sha((ART / (phase + '-probe')).read_bytes()) == result['binary_sha256']
    assert status['command'][0] == compile_status['command'][-1]
    assert status['command'][1:] == (['--require-bounded-self-comparison'] if '-work' in phase else [])
    output = (ART / (phase + '.log')).read_bytes()
    errors = (ART / (phase + '.stderr.log')).read_text()
    assert [l for l in output.splitlines() if l.startswith(b'compare ')] == expected_pairs
    assert result['ordering_pairs'] == 324
    linked = (ART / (phase + '-linked-libraries.txt')).read_text()
    assert not any(x in linked for x in ['AppKit', 'SwiftUI', 'WebKit', 'CoreText', 'CoreGraphics', 'QuartzCore', 'libgtk', 'libQt', 'libX11'])
    if phase == 'original-work':
        assert errors == 'SHARED_SUBTREE_WORK nodes=36866\nIdentical shared document descendants were traversed again\n'
        assert result['comparison_nodes'] == 36866
    elif phase == 'candidate-work':
        assert errors == 'SHARED_SUBTREE_WORK nodes=2\n'
        assert result['comparison_nodes'] == 2
    else:
        assert not errors and result['comparison_nodes'] is None
        assert output == expected_output
    if phase == 'candidate-sanitized':
        assert '-fsanitize=address,undefined' in compile_status['command']
assert receipt['qualified'] is True
verification = dict(source_head=HEAD, base=BASE, synthetic_checkout=checkout, source_tree=source_tree,
                    source_hashes_verified=len(paths), dependency_pins_verified=24,
                    ordering_pairs_per_phase=324, original_comparison_visits=36866,
                    candidate_comparison_visits=2, sanitizer_stderr_empty=True,
                    original_candidate_sanitized_complete_output_identical=True,
                    receipt_sha256=sha((ART / 'receipt.json').read_bytes()),
                    limitation='Local standalone C binaries independently rehashed. Component C semantics/ownership/work only; full hosted actual package/native qualification remains required.')
(ROOT / 'local-combined-c-independently-verified.json').write_text(json.dumps(verification, indent=2) + '\n')
print(json.dumps(verification, indent=2))
