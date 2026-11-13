# Static technical content in Quick Look

## Owner summary

MostlyText's installed Quick Look provider now renders ordinary GitHub Flavored
Markdown in a bounded, offline worker. The next user outcome is a readable
static equation or diagram in that same Finder window. Each failed item must
leave its own authored source visible without blanking the rest of the file.
The containing editor stays closed. This unit does not change live Preview,
HTML/PDF export, document bytes, or the final signed-install gate.

## Current source and reconciliation

Implementation now starts from main `482ca5c2`, which includes the Quick Look
GFM and source-compatibility candidates through PRs #254 and #255. Both passed
exact-head CI and genuine Finder qualification before merge. `QuickLookSource`
owns the selected descriptor, strict FileCore decoding, GFM fragment and escaped
fallback. The extension opens only the selected file, then sends its descriptor
to a sandbox-only service. Its child has a three-second parent deadline, a
3.5-second self-deadline and a bounded output file. The extension settles by
four seconds. None of these processes receives a parent-directory grant.

`MathContribution`, `MermaidContribution`, `D2Contribution` and
`GraphvizContribution` already produce generation-bound results for Export.
`DerivedContentComposer` and `CMarkGFM` already splice accepted output into
Markdown and preserve source on each rejected contribution. The production
math image renderer is main-actor SwiftUI/AppKit work; the three diagram
renderers use WebKit resources. The current child is synchronous, so merely
linking those renderers into it would not establish a working event loop,
containment or time budget. The source-only GFM result must not be cited as
technical-content acceptance.

## Prepared composition boundary

The local candidate adds a passive `ExportService` entry point for immutable
`ExportDerivedContribution` values. It reuses the export source-range,
generation, overlap, sanitizer and cmark custom-node rules. Quick Look's
stricter URL mode permits only internal fragments and raster data URLs in
generated markup; alternate resource attributes (`srcset`,
`poster`, `background` and `data`) are dropped. Authored Markdown URLs remain blank.
Per-item 1 MiB admission occurs before the sanitizer copies a fragment. The
shared composer charges its 4 MiB aggregate and 128-fragment ceilings only to
accepted placements, so stale and overlapping results cannot starve later
valid content. A refused item leaves its own source visible. These caps are
provisional pending Release renderer measurements.

Six focused package cases pass for accepted plus stale items, out-of-range
rejection, generated URL/script neutralization, oversized-item fallback and
budget starvation from stale/overlapping items. The selected-source suite
passes 11/11; existing sanitizer and derived-content suites pass 3/3 and
10/10. This candidate has no producer or worker caller, and establishes
neither document-derived math/diagrams nor Finder presentation of them. It
remains exploratory until its own exact-head CI review is complete.

## Pre-implementation feasibility gate

Before connecting the production contributor registry, run an exact-source
hosted macOS 26 probe inside the actual sandboxed worker identity. It must
prove one valid math image and one valid local-only Mermaid, D2 and Graphviz
SVG using the pinned resources and a running main actor/event loop. Record
request, renderer and reply times, peak memory, worker and WebContent PIDs,
entitlements, network-denial evidence, output bytes and normal teardown.
Give each producer a malformed/slow fixture and show that a later ordinary
file still renders. A result that needs a new network entitlement, parent
directory access, containing-app launch or an unbounded run loop stops this
architecture for review. A direct package renderer pass is not this probe.

The current exploratory branch adds a `QUICKLOOK_DERIVED_PROBE` build of the
same worker executable and a bounded hosted invocation before the existing
Finder test. Its first question is whether a static `x^2` PNG can be produced
inside the sandbox-only service without the containing app. This probe is
compiled out of the normal worker and does not route document math to Finder;
Mermaid/D2/Graphviz, failure isolation, and complete budget/containment proof
remain subsequent gates.

At `7f8b49b8`, hosted run 43360005605 answered that first question: the
ad-hoc signed sandbox-only worker exited 0 and produced a 1,847-byte PNG in
0.919 s wall time (0.693 s renderer-reported elapsed), with 24,625,152-byte
peak child RSS reported by the harness. The subsequent genuine cold Finder
source test passed 1/1, including ordinary, symlink and UTF-16 BE cases. This
does not establish a document producer/caller, varied equations, theme
contrast, renderer cancellation or a final Release budget. The issue #7
checkpoint records the exact scope.

At `6849c83e`, hosted run 43363675213 invoked the repository's
`SharedMathContribution` on fixed Markdown, then admitted its generated PNG
through the passive `ExportService` composer. The async main-run-loop path
exited 0 with 2,560 HTML bytes in 0.242 s wall time (0.217 s worker-reported;
25,624,576-byte harness peak child RSS). The direct image probe and subsequent
cold Finder source control also passed, the latter 1/1 with no timeout or
cancel. This establishes fixed-source feasibility in the sandboxed worker;
the compile-flagged probe does not consume a selected file or publish
document-derived math to Finder. Local locked Release compilation, source
lint and the 67-sink audit also pass.

## Production boundary after the probe

Keep `QuickLookBoundary` as the small XPC status and byte-cap product.
`QuickLookSource` continues to own file admission and FileCore decoding.
Add a worker-only composition product that calls the existing shared parse,
contributor and export composition contracts. The app-host test bundle must
not link that product through its process-controller tests. The worker owns
one immutable source snapshot and generation for the request. Its per-item
results carry the same source ranges and diagnostics as Export; accepted SVG
or data-image output passes the existing resource/markup validation before
it enters the HTML fragment. The passive source URL policy still blanks every
authored link and image URL. Only validated generated data images and inline
SVG may be admitted by a narrowly revised CSP. No file or network URL enters
the reply; no generated item can authorize a sibling read.

Run contributors independently within one overall worker deadline and their
own measured limits. A malformed, over-budget or timed-out item contributes
no HTML; its source remains in the GFM body. The current process-wide timeout
returns no reply, so production technical rendering also needs an immutable
source-only reply completed before any renderer starts. Keep fallback and
derived bytes in separate bounded output slots; if a child times out, the
parent may publish only the complete fallback, never partial derived bytes.
Do not increase the existing three/four-second deadlines on a guessed
performance claim. If complete technical rendering cannot fit, record the
measured counterexample and revise the architecture before implementation.
Renderer completion, XPC reply and child exit each settle once. Late callbacks
after cancellation or teardown cannot publish another generation.

An exploratory process-boundary implementation now allocates separate unlinked
fallback and derived output slots. The child writes a one-byte `F` completion
marker only after the source reply is complete; a later derived reply requires
an additional `D` marker after its own complete write. On the three-second
deadline, the parent kills/reaps the child and accepts only a marked, bounded
source fallback. A new controlled fake child writes partial derived bytes and
then stalls; its test requires the complete source fallback and reaping. The
exact worker and app/test bundles compile locally in Debug with locked pins;
hosted execution and real Finder regression remain pending. This fallback
prototype alone does not render document-derived content.

The next exploratory build flag, `QUICKLOOK_DERIVED_MATH`, now reads the
selected immutable source after the fallback marker, invokes
`SharedMathContribution`, adapts its static results into the passive composer,
and marks a separate derived output only after the complete write. A source
without a dollar marker remains on the ordinary source path. Local locked
Release compilation and source lint pass. The new Finder fixture requires an
accessible `x^2` image from the selected file; hosted execution and visual
review are pending. This flag is not enabled in the normal product build.

## Qualification and stop conditions

Use package tests for valid/invalid source ranges, independent per-item
fallback, authored URL neutralization, generated-output validation and exact
byte caps. Use genuine installed-provider Finder tests for ordinary GFM,
each technical format, mixed good/bad items, symlink selection, repeated
open/close and a slow/failed item followed by an ordinary file. Measure
Release ordinary and technical latency separately, as well as memory and
WebContent retirement. Run full locked CI, compliance and final source/pin
checks on the exact head. Keep final signed clean-install, theme/locale and
human visual acceptance under issue #7 until performed on the final artifact.
