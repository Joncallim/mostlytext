# First original-focus preparation outcome

Sourceb87ceeac/run42330490485 genuinely builds the Debug app and original
test bundles. The subsequent settings-only command wrongly includes a test-
only coverage option, is explicitly refused, and leaves zero JSON bytes.
Private-control build/execution and original UI execution are skipped; zero
UI cases ran. All1605 source inputs,24pins and seven generated private-control
files are independently verified. The source assertions and product are
unchanged. Full raw build log/plans and full job ZIP are retained separately.

A local standalone tool-only generated project reproduces the exact parser
refusal64; omitting only that option returns valid settings JSON0, including
with the same ad-hoc identity override. No app target/build/registration or
native test executes locally. The correction removes the option only from
showBuildSettings, retaining it for actual build/test actions. All original
counts, selection, assertions, guards and deadlines remain unchanged.

The first local evidence script failed because its synthetic commit was not
yet fetched. A missing shell failure stop let an architecture-only commit7ad5
push and trigger an unintended identical-input run42331730880. That run is
explicitly stopped/preserved, never a qualification or green rerun. The old
synthetic commit was recovered from the already verified independent ALL-ref
restore; the evidence check then completed before the actual correction push.
