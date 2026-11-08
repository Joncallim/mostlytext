#!/usr/bin/env python3
"""Source-preservation and SDK typecheck only; never link or execute a native product."""
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path('MacDown2/MacDown2Tests')
ORIGINAL = {
    'ProductionPreviewResourceRoutingTests.swift': '6cbbb9a8ae36abb8b09dcd9437c084a5e125383fe97f403078ebfce95efc52f4',
    'SecuredMarkdownMountedTests+Support.swift': '3b280acc58f84ca1d30d0468d47675496a0177e536210bc3ee9210eac980d274',
}
OLD_ARGS = '''            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0'''
NEW_ARGS = '''            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0'''

for name, digest in ORIGINAL.items():
    source = (ROOT / name).read_text()
    normalized = source.replace('import Textual\n', '')
    normalized = re.sub(r'^ *MostlyTextPublicationTrace.markCopyFailure\("[a-z-]+"\)\n', '', normalized, flags=re.MULTILINE)
    if name.startswith('Production'):
        if source.count(NEW_ARGS) != 1:
            raise RuntimeError('Bitmap arguments changed beyond the exact reviewed formatting')
        normalized = normalized.replace(NEW_ARGS, OLD_ARGS)
    if hashlib.sha256(normalized.encode()).hexdigest() != digest:
        raise RuntimeError('Original assertions, calls, deadlines or cleanup differ: ' + name)

source = (ROOT / 'ProductionPreviewResourceRoutingTests.swift').read_text()
start = source.rindex('        Issue.record(')
statement = source[start:source.index('\n    }', start)]
if not statement.startswith('        Issue.record("""\n') or not statement.endswith('\n        """)'):
    raise RuntimeError('Restore the original Swift Testing Comment literal')
lines = statement.splitlines()[1:-1]
if len(lines) != 2:
    raise RuntimeError('Unexpected original diagnostic message')
negative = 'Issue.record("' + lines[0].strip() + '\\n"\n + "' + lines[1].strip() + '")'
wrapper = '''import Testing
struct Harness { func copyDiagnostics(in root: Int) -> String { String(root) } }
struct Fixture { let copyHarness = Harness() }
func checkMessage(lastRaster: String, lastHTML: String, root: Int) {
    let fixture = Fixture()
    let location = SourceLocation(fileID: "Fixture/Message.swift", filePath: "Message.swift", line: 1, column: 1)
%s
}
'''
platform = Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-platform-path'], text=True).strip())
frameworks = platform / 'Developer/Library/Frameworks'
if not (frameworks / 'Testing.framework').is_dir():
    raise RuntimeError('The selected Xcode must provide the actual Testing SDK framework')
with tempfile.TemporaryDirectory(prefix='mostlytext-comment-typecheck-') as folder:
    path = Path(folder) / 'Message.swift'
    for label, expression, should_pass in [('original-literal', statement, True), ('joined-literal', negative, False)]:
        # Supply only the unrelated location explicitly to avoid running a compiler macro plugin.
        expression = expression[:-1] + ", sourceLocation: location)"
        path.write_text(wrapper % expression)
        result = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '6',
                                 '-strict-concurrency=complete', '-warnings-as-errors', '-F', str(frameworks), str(path)],
                                capture_output=True, text=True, timeout=30)
        if (result.returncode == 0) != should_pass:
            raise RuntimeError(label + ' SDK typecheck has an unexpected outcome: ' + result.stderr)
        if not should_pass and "referencing operator function '+'" not in result.stderr:
            raise RuntimeError('Negative control failed for a different reason: ' + result.stderr)
        print(label, 'typechecks' if should_pass else 'correctly refuses the original overload error')
print('Both complete original test files reproduced after only diagnostic/format normalization; no runtime executed')
