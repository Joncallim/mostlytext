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
