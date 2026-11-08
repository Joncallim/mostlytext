# Keep inline Preview styling bound to its current input

## Owner summary

A loaded document image can still copy as stale placeholder text. Change the
smallest renderer layer that prevents this observed failure: derive inline style
from the input being rendered, rather than publish a second optional copy later.
No resource permission, parsing policy, image loader or selection authority changes.
The larger text-builder cache experiment is rejected because it still fails the
normal journeys. The actual integration candidate must pass without diagnostic
instrumentation before this correction can merge.

## Ready baseline and reconciliation

Current main is `a46c57c4b62376b67492cf67421a4961fdf55c1c`, including qualified
PDF layout, fixed canary and final documentation. Canonical PR146 is frozen at
`6cad56275c1d9a71a9ee95daa066bd1fcae68965`; all fourteen complete firsts are
retained, with thirteen passing and the six-pair Preview workflow failing.
Inspect and reconcile current main before final implementation publication.
AGENTS.md, EPIC_STANDARD.md and RELEASE_HARDENING.md remain binding.

The [minimal-layer evidence](evidence/renderer-minimal-layer-qualified-firsts-2026-11-08/README.md)
comes from three complete first native variants at source `bf67f10c`, run
[42448090646](https://github.com/Joncallim/mostlytext/actions/runs/42448090646),
with [Compliance 42448095986](https://github.com/Joncallim/mostlytext/actions/runs/42448095986).
Each executes all 57 standalone originals plus one aggregate of 24 fresh journeys.
Original has eight unforced normal issues; fragment-only also has eight;
inline-only has zero and passes all twenty normal journeys. Intentional faults
produce six / three / three further issues respectively, so the aggregate and
whole native workflow correctly remain failed in all three variants. All actual
source, effective dependency, compiled roles, raw results and owned exits are
independently verified. Earlier firsts, including compile-only failures, remain
preserved. No diagnostic result is retargeted as a shipping qualification.

Markers now precede failure diagnostics, but traces are global across instances.
Attachment-bearing updates appear before failed deadlines; that does not identify
every visible instance or prove a sole framework, missed or late callback cause.
The selected fix follows the functional differential and the invariant below.

## User journeys

Open the real Markdown window with a granted image, copy it through the native
selection, change the image/document generation and copy the new pixels. Change
source, grant, root or visibility while loading: preserve existing revocation,
stale-result refusal, retained scroll container and exact fresh clipboard ownership.
HTML Preview, math, headings, export and CLI keep their existing contracts.

## Invariants and ownership

Textual's private WithInlineStyle owns only applying the existing inline styles.
Its body must supply the resolved value of its current input/style/environment to
its content closure in that evaluation. There is no empty initial placeholder or
second State publication. The existing pure run-by-run style merge is unchanged.
Other attachment and builder caches, resource identities, source/pin authority,
fonts, license/resource bytes and public APIs stay unchanged.

## Types and data flow

Remove WithInlineStyle's optional @State output and onChange callback. Its body
calls the same private resolve function with current input/style/environment;
resolve returns AttributedString instead of assigning State. The candidate is
exactly the qualified inline-only source with its two trace expressions removed.
Only that one upstream Swift file changes relative to immutable pin
`dd123d4f7052d84032cafb22c62cd467916518dd`. All other 295 tracked fork files stay
byte-identical, including TextFragment, TextBuilder, loaders, tests and MIT text.
No new cache type or module dependency is introduced.

## Concurrency, cancellation and lifetime

Styling remains synchronous in the existing SwiftUI view actor context. No task,
callback, observer, request identity, geometry or retirement policy is added.
Removing derived State eliminates its asynchronous publication boundary without
altering upstream attachment request ownership or downstream builder lifecycle.
The canonical tests keep their original source, assertions and five-second limits.

## Failure model and trust boundary

Existing parse/resource denial, unavailable images, cancellation, load failures,
HTML request/root/MIME rules and exact-once handlers remain authoritative. The
fix cannot manufacture an image, URL authority, accepted contribution or clipboard
write. No diagnostics, fault-suppression guards, trace helper, failure markers or
private aggregate test enters the shipping fork or canonical test files.

## Resource and performance budgets

The style loop remains linear in input runs. Existing Preview input budget is
64 KiB, with oversized blocks taking their current literal fallback. Styling now
occurs in body evaluation; repeated evaluations may perform additional work.
Do not claim a whole-app latency or memory improvement. Preserve all existing
bounds and full Release/functional gates. If those reveal a material regression,
stop and revise this design before inventing an unqualified memoization layer.

## Accessibility, localization and interoperability

No user-facing text or catalog changes. Existing inline emphasis/code/link intent,
attachment metadata, native selection, math labels/actions, heading navigation
and HTML copy must survive the same original qualification. The source document,
export bytes/policy and durable formats do not change from this styling fix.

## Immutable dependency and attribution update

Create a descendant in the owned Textual fork. Compare all original/effective
tracked bytes and preserve MIT/resources. Deliberately update that single revision
in Package.swift, Package.resolved, project.yml and the existing inventory source
reference. Regenerate notices/SBOM with the established tool; record exact scope
and evidence. Do not run local package resolution, builds or native products.
This is technical dependency accounting, not independent rights clearance.

## Native checker reconciliation

The existing serialized mounted suite has four original functions after the
fresh-clipboard regression was added. Both native controllers still expect three.
Change revision/disappearance mutant and restored selections to four in BOTH
check-preview-parsed-frame.py and verify-preview-grant-probe.py. Require the
existing aNoWriteNativeCopyCannotReuseAnEarlierImage positive to pass in either
mutant along with the existing unaffected controls. Keep the one intended failure,
exact owned result, compiled binding and network controls. Do not move the test
out of the suite or remove any original assertion or selection.

## Test and adversarial evidence

The prior three-variant firsts are failing-before evidence for the unchanged real
image/revision functions. Shipping validation uses the original uninstrumented
Debug/Release six-pair gate, initial and selection tests, actual counterfactuals
and exact restorations. Preserve fresh clipboard/no-write refusal, hostile network
positive controls and all original resource/lifetime cases. Obtain all fourteen
current combined-source first workflows, including full package/app/four builds,
UI matrix, native PDF, canvas, math/heading/geometry/public CLI and Compliance.
Read actual source/pin/compiled/result/owned records, not only green check badges.
Local checks are pure Python/C/Foundation where permitted, syntax/SDK typecheck,
format/lint and evidence readback only. No owner account native or engine runtime.

## Slices, expected files and stop conditions

1. Commit this architecture and exact first evidence before fork implementation.
   Reconcile main into PR146 without publishing intermediate qualification sources.
2. Change the one private fork Swift file and prove all other bytes identical.
   Publish its immutable revision, then deliberately update pins/inventory/generated
   notices and the two native checkers. No project target or public API changes.
3. Review and freeze one complete candidate, obtain all required firsts and retain
   whole outcomes/artifacts before correction. A real failure stops readiness;
   do not retry unchanged failed source, pad deadlines or waive an assertion.
4. Merge only after exact source/tested/computed/current-main tree and ownership
   verification. Update owning issues with the scoped integrated behavior.

## Definition of done and remaining gates

A qualified uninstrumented canonical candidate, correct dependency accounting,
strict style and full required firsts must precede merge. Independent rights,
owner/separate-account, complete parity/visual/performance, signing, exact signed
artifact and release acceptance remain separately open. No whole issue closes
from this renderer correction alone. A later ordinary export activation must
consume the qualified renderer and current PDF helper and run its own real menu,
Cancel, external PDF validation and normal Quit.
