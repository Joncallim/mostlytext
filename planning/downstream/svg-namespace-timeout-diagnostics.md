# Identify the renderer behind the namespace fixture timeout

The Intel package run for PR68 failed before its SVG ownership assertions. Its
single combined test hides whether Graphviz, D2, Mermaid or the canvas harness
failed. Collect a narrowly scoped, repeatable comparison before changing any
renderer, timeout or assertion. This is diagnostic evidence, not native acceptance.

## Baseline and contract

Main is `dbbd6f4f69d3f4712801205cbd92308d9244870d`; PR68's attribution-only
head is `7ead272c0022108baacfd7db28dab8af86c446ad`. Their MacDown2 trees are
identical. CI 41856165565 reports `timedOut` after 17.247 seconds in
`RealSVGNamespaceTests.ownedRendererOutputsRemainAdmissibleAndD2FallsBack`.
This is not proof that the failure is pre-existing or a harmless timing issue.
Retain that first failure and keep PR68's complete source CI gate.

## Bounded experiment

Add a separate read-only hosted workflow for those two immutable revisions on
Intel macOS 26. Check out each exact revision without credentials. Record source
and lock identities. Add only timestamped phase prints to the owned runner's
test source, with exact unique anchor checks and retained before/after hashes.
Keep every original statement, resource, deadline, assertion and renderer intact.
Compile locked tests and use the same owned, ad-hoc-signed Swift Testing helper
as complete CI; never modify Xcode or execute local product/AppKit/WebKit code.

Run just the failing case twice in fresh test processes. Preserve both exit
statuses even if one fails; fail the job if either fails. Upload bounded relevant
logs and identity receipts on success or failure. A pass is a diagnostic data
point, not a replacement for the original failure or the full-suite gate. A
reproduced baseline failure establishes scope but does not explain its cause.

Stop and reconcile unexpected checkout/source/lock changes, an unsupported host,
or any need to alter test semantics. Product behavior, renderer implementation,
package pins, existing CI, attribution records, native receipts and release guards
are outside this diagnostic unit. Track results in #17 and PR68; propose a
separate evidence-led remediation only after identifying the failing phase.

## Follow-on question: the first D2 render on an Intel test host

The original narrow comparison is complete: both immutable revisions execute
the same original/instrumented fixture bytes, with all four attempts passing.
The fresh full ARM build/test job passes 3,430 package tests and 619 app tests.
The fresh full Intel job instead fails `D2WebRendererTests`' first simple render
after 15.043 seconds; its namespace case passes. Preserve both actual failures;
neither is proved pre-existing by an identical tree or a passing retry.

The D2 error maps a shared-pool timeout; 15 seconds is consistent with admission,
but elapsed time alone does not distinguish page construction/navigation,
engine readiness and later script execution. The older namespace canvas helper
also maps content-process death to `timedOut`, so its first failure cannot be
classified from that string alone. Do not change either production deadline.

Run a second bounded experiment on exact base `dbbd6f4f...` in two fresh Intel
VMs. Both run only D2's first simple-render case twice in fresh helper processes.
One keeps its original test setup; the other explicitly initializes
`NSApplication.shared` before creating the renderer, as a diagnostic control
for the difference between a CLI test host and an already running app. This is
a fixture experiment, not a proposed production workaround or accepted fix.

Add only marked phase prints inside the existing main-actor page creation/load,
D2 engine readiness and render paths. Record whether NSApp is nil immediately
before/after the existing web-view construction; the control must not make an
extra main-actor hop or initialize NSApp before its original renderer call.
The initialized variant adds one explicit main-actor initialization outside the
renderer. No activation, window, permissions, source upload or owner-account
execution is involved. No document/fence content is logged.

Every added import, print and initialization statement has one diagnostic
marker. Removing only those complete lines must restore every original byte
of each affected file. Preserve per-file before/after hashes, the setup flag,
exact source/tree/lock/toolchain/helper identities and both attempt statuses.
Each job fails if either attempt fails; do not invent success or force a failure.
Manual dispatch retains the completed namespace comparison; PR updates exercise
this new cold-D2 question instead of repeating the old comparison.

Validate YAML/shell/Python syntax and insertion/round-trip on owned copied source
files locally, without executing Swift/AppKit/WebKit. Hosted compilation and
actual cases validate the experiment. If the original setup already has NSApp,
or neither variant reproduces the failure, do not call initialization its cause.
Use observed phases to choose the next step. Stop on ambiguous anchors, changed
original statements, unrelated source changes or any need to weaken a budget.
