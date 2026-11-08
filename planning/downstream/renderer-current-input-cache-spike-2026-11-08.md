# Test current-input rendering when a derived-state update is withheld

## Owner summary and narrow question

Preview must not copy stale plain text after its image loader has supplied a real
attachment. The canonical6cad candidate has two actual Release failures with that
symptom. Stage tracing and twenty fresh scenarios have since passed; those runs
do not identify the original missing stage and instrumentation can change timing.
Keep PR146 and production dependency pins frozen. This is a named, never-merge
pre-implementation experiment, not a shipping fix or a sole-cause claim.

Test a specific invariant: can withholding an attachment-bearing update to either
of the renderer's two derived-state caches leave Copy plain, and can rendering
from the current input in the same view evaluation prevent that fault? The
controlled fault is hypothetical, not a claim that SwiftUI missed either callback
in the original failures. A positive prototype would justify a separate production
architecture and uninstrumented qualification; it would not itself merge a fork.

## Live baseline and completed evidence

Live main isf12d6d357a2a67087db7022060fae798733d3ce7. Canonical preview source
remains6cad56275c1d9a71a9ee95daa066bd1fcae68965. The diagnostic branch9cce9dbc
leaves all product sources, dependency pins and original tests equal to6cad and
adds only one diagnostic test. Complete first native42440909585 and Compliance
42440922359 pass. Actual58functions=57original+1aggregate invoking20freshjourneys;
zero skips/expected/failures, owned81.004seconds/exit0/no force or timeout.
All296original/297effective fork files,24pins,5downloaded compiled roles, actual
host facts and22buffer JSONs are independently verified. Initial buffer is empty
because the aggregate ran first; no complete original57stage trace is claimed.
All complete firsts/logs/raw outputs are retained before this new decision.

The original current Textual pin isdd123d4f7052d84032cafb22c62cd467916518dd.
WithInlineStyle stores styled output in State, updates it through onChange of
input/style/environment, and renders that prior output. TextFragment separately
stores an optional TextBuilder through onChange(content). Its geometry callback
may update the retained builder. TextBuilder itself caches at most10 rendered
Text values keyed by actual attachment sizes. These are distinct ownership and
publication steps; no actual original callback failure has been observed.

## Variants, inputs and controlled failure

Use one manual hosted Release workflow with variants original and current-input.
Both compile the exact actual app and original57selection plus the diagnostic
aggregate, with original assertions,5second waits, native network controls,
source/compiled binding and600second owned bound unchanged. Each disposable VM
patches only its verified actual Textual checkout; no local SPM/native execution.

Keep the existing four original-file digest gates and complete before/after
source capture. Record the selected variant in effective-source and app receipts,
forward its fixed public value to the child, and archive every modified source.
Original pin metadata is unchanged but effective compiled source IS MODIFIED.

Extend the fixed aggregate from20to24declared fresh scenarios: ten normal rounds
of both original failing functions, one round with inline-update suppression,
one round with fragment-update suppression. Source/window fixtures remain fresh
on every invocation. Reset the diagnostic fault in defer so original57tests run
without it, regardless of test ordering. No retries until green or withKnownIssue.
Every thrown/nonfatal assertion remains a native test failure and is retained.

The diagnostic-only helper selects none/inline/fragment and records the selected
fault with each bounded buffer. In the ORIGINAL variant, a guard inside the
existing corresponding onChange callback suppresses only attachment-bearing
updates, recording the actual suppression. Plain initial updates still execute.
All other original statements and normal callbacks remain. In the current-input
variant those two publication callbacks no longer exist, so the fixed fault
cannot withhold a required deferred cache update. Record that structural fact;
do not claim a callback was suppressed where there is none.

The original variant is expected to FAIL the aggregate's four controlled fault
scenarios while original57and20normal scenarios pass. Preserve its actual exit65,
raw test issues, per-scenario records and compiled/source hashes. It is an intended
negative first, not a waived product failure or a green canonical qualification.
The prototype variant must pass all58functions and24scenarios with zero skips,
expected failures, timeout, forced cleanup or overflow. Unexpected negative
results or a nonfailing original fault remain explicit nonqualification.

## Current-input prototype contract

WithInlineStyle computes the same styled attributed string directly from current
input/style/environment inside body and passes it to content. Preserve the exact
style merge loop and keepNew policy. Remove its intermediate optional State and
onChange publication. No new public API, timer, observer or asynchronous stage.

TextFragment retains a private MainActor BuilderCache reference in State. The
cache resolves synchronously during body and reuses a builder only when BOTH its
Content value and TextEnvironmentValues match current input. Otherwise construct
a builder immediately from current content/environment. Preserve TextBuilder's
existing10entry size cache and original attachment/link attributes. Keep at most
one current content/environment/builder and the last observed container size.
If a size is known, apply it to a replacement builder before rendering its text.

The existing geometry callback updates the cache only when its captured builder
is still the cache's exact current builder; a stale callback cannot modify the
new builder. It records the last size and calls the unchanged sizeChanged method.
Body renders the resolved builder's observed text. Remove the independent content
onChange publication; keep selection/attachment/link modifiers and the existing
geometry observer. Cache-key mutation is private memoization, not another
observable publication during body. No unbounded map or global resource owner.

This deliberately changes the prototype's publication architecture. Previous
claims of an unchanged observer graph apply only to earlier tracing variants,
not this named experiment. The public shipping fork stays untouched until native
fault/positive evidence and a separate final architecture justify a real change.

## Limits, validation and next decision

Keep the4000event per-scenario limit and capture overflow as failure. Do not log
authored text/URLs or arbitrary environment. Source/AST/style/pure-transform tests
run locally only; actual typecheck/build/render/copy is on guarded macOS26ARM.
Variant and fixed-case identity, all before/after bytes,5actualcompiledroles,
owned process and raw results must be independently checked. Preserve both
complete first variants and Compliance before any correction or new publication.

A successful prototype still requires uninstrumented full Debug/Release native
Preview/mutation qualification, full package/app/CLI CI, theme and size behavior,
provenance/pin/inventory reconciliation and review before any production merge.
It cannot establish the original OS/event cause, whole issue13or15closure,
owner-account acceptance, signing or release readiness. If the original controlled
fault does not produce the expected publication loss or the prototype introduces
layout/performance/lifecycle regressions, stop this remedy and retain the result.


## Observed real failures, timing limit and minimal-layer follow-up

Current live main is7867621005a65950bb0db994b8cddaa2f5367412, including qualified
PDF correction and final evidence. That code remains separate from this never-merge
branch based6cad. Complete first395native42443157406 is FAIL: original fails,
current-input passes. Compliance42443169680 passes. All raw firsts/logs/artifacts
and exact source/compiled bindings are retained before this revised decision.

Both variants COMPILED and ran. A completed-job step snapshot lagged at Compile;
actual logs/results, not that stale step field, establish execution. Original
actual58functions=57standalonePASS/1aggregateFAIL13issues, owned65/138.100seconds,
no force/timeout/skip/expected failure. Seven issues occur in NORMAL unsuppressed
scenarios:00revision,01revision,02revision,03revision,05revision,06production,
08revision. Four injected fault scenarios produce six further issues. These are
real baseline failures, not all intentional negatives or passing normal controls.
The prototype passes all58functions and24freshjourneys, owned0/56.244seconds.
Both actual hosts are26.7.2/25G332. All296original/297effective dependency files,
five exact modified Swift files,24pins and five downloaded compiled roles per
variant are independently verified. No production fork/pin change is made.

The original fixture uses nonthrowing Issue.record. Therefore threw=false records
only the absence of a thrown error; it MUST NOT be used as a per-scenario pass.
Raw native issues and result summaries remain authoritative. Within the single
serialized aggregate, actual issue events are indexed to the following fixed
end-of-scenario record; all13are retained without changing assertions.

Completed failed01revision and passing04revision buffers have identical stage
counts, including attachment-ready, inline change/resolution, fragment change,
attachment-bearing builder construction and size updates. This does NOT establish
that those events preceded failed Copy: existing failure diagnostics can await
and process more work before the final archive. There is no failure-point marker
or comparable clock in these firsts. Missing or late callbacks and the original
OS/framework cause remain unproved. Do not select a production fix by claiming
that the prior trace proved a missed callback.

Run a new narrow comparison of original, inline-only and fragment-only. Do not
repeat the unchanged combined positive variant. Compose each partial prototype
from the exact already-qualified current-input file for that layer and the exact
original traced/suppression file for the other. This determines which minimal
publication change addresses actual normal-scenario loss and avoids unnecessary
per-body style work if the fragment cache alone suffices. It changes no product
contract, authority, source pin or canonical PR146 yet.

Before the next run, add a failure-only marker to the private test source so
MainActor buffer order can be related to the actual failed deadline. The marker
appends a fixed label with an empty attributed string; no authored content,
I/O, clock, timer, preference/geometry observer or normal-path state change.

- In SecuredMarkdownMountedTests+Support, mark the caught Copy-command refusal
  BEFORE captureFailure/awaitdiagnostic. Also mark after the outer five-second
  loop expires, BEFORE captureFailure and the diagnostic await.
- In ProductionPreviewResourceRoutingTests, mark after replacement-image Copy's
  unchanged deadline loop expires, BEFORE its original Issue.record.

Keep every original assertion, error, return, loop, deadline and cleanup statement.
These TWO existing test files are deliberately instrumented in this never-merge
branch; add their Textual imports and bind the actual changed sources. Do not
claim byte-identical original tests for this follow-up. The production app source
stays equal to6cad; only private test diagnostics differ. Canonical PR146 files
remain untouched. Receipt metadata explicitly identifies failure-only markers.

Retain all24fixedscenarios/58outerfunctions,4000events per scenario, original
network/ownership/source controls and600second executor. Each variant still has
its own complete original/effective source, selected variant, compiled roles,
actual host, raw results and scenario buffers. Update pure exact-source controls
so partial variants cannot silently replace the unselected layer or omit its
controlled suppression. Freeze once and obtain all three complete native firsts
and Compliance before any correction or publication of a production remedy.

No source rights decision, owner-account native run or release acceptance follows.
Only after minimal source/native evidence should a separate shipping architecture
remove diagnostic helpers, make any actual fork/pin/compliance change, reconcile
current main into PR146 and obtain all uninstrumented canonical qualification.


Local implementation note: the production-image failure message uses two joined
ordinary string literals instead of a multiline literal, preserving its exact
newline and interpolation arguments. This keeps the diagnostic marker within the
existing strict function-length rule without disabling a warning or moving an
assertion. Source comparison removes only the new imports/markers and normalizes
that equivalent literal representation, then reproduces both original test files
byte for byte. Every original assertion/control/cleanup statement is retained.
