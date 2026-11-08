#!/usr/bin/env python3
"""Command-line-only control for the private per-request worker code."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / '.github/quicklook-jsc-probe/XPCService/WorkerBoundary.swift'
HARNESS = ROOT / '.github/quicklook-jsc-probe/WorkerBoundarySmoke/main.swift'


def compile_and_run(folder: Path, source: Path):
    binary = folder / 'QLReplyProbeXPCService'
    subprocess.run(['swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-O',
                    str(source), str(HARNESS), '-o', str(binary)], check=True, timeout=60)
    return subprocess.run([str(binary)], capture_output=True, text=True, timeout=8)


def main():
    with tempfile.TemporaryDirectory(prefix='mostlytext-worker-control-') as path:
        folder = Path(path)
        positive = compile_and_run(folder, SOURCE)
        if positive.returncode or not positive.stdout.startswith('PASS: held=timedOut normal=completed distinct=1 normalAfterHeld=1'):
            raise RuntimeError(f'Bounded concurrent worker control failed: {positive!r}')
        mutant = folder / 'unbounded-normal.swift'
        original = SOURCE.read_text()
        changed = original.replace('mode == .normal ? 1.55 : 10', 'mode == .normal ? 10 : 10')
        if changed == original:
            raise RuntimeError('Negative-control mutation no longer applies to the worker fixture')
        mutant.write_text(changed)
        negative = compile_and_run(folder, mutant)
        if negative.returncode != 1 or 'FAIL: normal child must complete' not in negative.stderr:
            raise RuntimeError(f'Unbounded normal worker did not fail the control: {negative!r}')
        print(positive.stdout.strip())
        print('PASS: delayed-normal negative control fails before hosted Finder acceptance')


if __name__ == '__main__':
    main()
