# Reproduce the replacement-plan bounds proof

These procedures run only the copied Foundation/Darwin modules and their owned
temporary-file tests. They do not launch MostlyText, its CLI, AppKit/WebKit or
native acceptance. The original protected-account hold remains in force.

The qualified source is PR61 head
`d23ce9847515529ed785b0155a39dfd77e84dc5d`. [source-files.json](source-files.json)
pins every one of the 86 source/resource/test files. No import substitutions,
adapters or stubs are used. [validation.json](validation.json) records the
original toolchain, actual results and retained log hashes. A mismatch must stop
fixture preparation; do not rewrite the frozen manifest to fit a newer source.

## Prepare a fresh owned fixture

Set MT_SOURCE to a checkout whose copied files match the qualified manifest.
MT_PROBE must name a new directory under owned scratch storage. The script
checks every source byte before creating that directory and copies only the
manifested files plus the independent package definition.

```sh
export MT_SOURCE='/path/to/qualified-mostlytext-checkout'
export MT_PROBE='/path/to/new-owned-scratch/replacement-plan-probe'
python3 - <<'PYTHON'
import hashlib
import json
import os
from pathlib import Path
import shutil

repo = Path(os.environ['MT_SOURCE']).resolve()
probe = Path(os.environ['MT_PROBE']).resolve()
if probe == repo or repo in probe.parents:
    raise ValueError('Probe must be owned scratch outside the source checkout')
packet = repo / 'planning/downstream/evidence/replacement-plan-range-bounds-2026-11-04'
package = repo / 'MacDown2/Packages/MacDownKit'
records = json.loads((packet / 'source-files.json').read_text())
for record in records:
    relative = Path(record['path'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Unsafe manifest path')
    source = package / relative
    if hashlib.sha256(source.read_bytes()).hexdigest() != record['sha256']:
        raise ValueError('Qualified source differs: ' + record['path'])
probe.mkdir(parents=True, exist_ok=False)
for record in records:
    source = package / record['path']
    target = probe / record['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    if hashlib.sha256(target.read_bytes()).hexdigest() != record['sha256']:
        raise ValueError('Copy differs from qualified manifest: ' + record['path'])
shutil.copyfile(packet / 'FixturePackage.swift', probe / 'Package.swift')
print('All 86 manifested files copied exactly')
PYTHON
```

Run the entire TextSearch corpus in both configurations:

```sh
swift test --package-path "$MT_PROBE" --no-parallel
swift test --package-path "$MT_PROBE" -c release --no-parallel
```

The recorded result is 131 tests / 20 suites passing in each configuration. Five
new methods prove negative/extreme/overflow/ordinary bounds, a corrupt suffix
after a valid match, preview refusal, unchanged original bytes and continuation
to the next valid file. Positive cases cover empty plans, zero-width boundary
matches, adjacent Unicode ranges and CRLF adaptation. These are source/disk
engine results; final mounted-app folder replacement remains a separate criterion.

## Reproduce the actual old-source crashes

Use a separately prepared owned fixture, retaining the new tests. Replace only
its production ReplacementPlan.swift with that exact historical file from
baseline 17b1e7a011ff0724fa480ce4fc2290a245b033bd. Nothing in the checkout changes:

```sh
python3 - <<'PYTHON'
import os
from pathlib import Path
import subprocess

repo = Path(os.environ['MT_SOURCE']).resolve()
probe = Path(os.environ['MT_PROBE']).resolve()
if probe == repo or repo in probe.parents:
    raise ValueError('Probe must be owned scratch outside the source checkout')
if '"ReplacementPlanBoundsProbe"' not in (probe / 'Package.swift').read_text():
    raise ValueError('Historical file may only replace an existing owned fixture source')
source = 'MacDown2/Packages/MacDownKit/Sources/TextSearch/ReplacementPlan.swift'
body = subprocess.check_output(
    ['git', 'show', '17b1e7a011ff0724fa480ce4fc2290a245b033bd:' + source], cwd=repo)
(probe / 'Sources/TextSearch/ReplacementPlan.swift').write_bytes(body)
PYTHON
swift test --package-path "$MT_PROBE" --no-parallel \
  --filter ReplacementPlanRangeBoundsTests/overflowingEndsAreRejectedBeforeAddition
swift test --package-path "$MT_PROBE" --no-parallel \
  --filter ReplacementPlanRangeBoundsTests/negativeLengthsNeverReachFoundationReplacement
```

Run the two filters separately. Each actual old-source run exits nonzero with
an uncaught Foundation NSInvalidArgumentException reporting an out-of-bounds
replacement. A compiler failure or unrelated crash is not that negative proof.
The original overflowing-end case reaches Foundation after a wrapped endpoint
comparison; no Swift arithmetic-trap claim is made. Preserve original failed
logs. Restore the qualified file or create another fresh fixture before the
positive full-suite runs; do not reuse the historical file for passing evidence.

Original logs, both manifests and local validation remain under
`/Volumes/Fast SSD/CORTANA-Builds/replacement-plan-range-bounds-20261104`.
Complete hosted source-build evidence is linked on [PR61](https://github.com/Joncallim/mostlytext/pull/61).
Native UI, installed-state, signing and final artifact acceptance are not inferred.
