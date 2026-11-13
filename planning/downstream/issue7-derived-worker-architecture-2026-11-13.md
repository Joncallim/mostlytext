# Static technical content in Quick Look

## Owner summary

MostlyText's installed Quick Look provider now renders ordinary GitHub Flavored
Markdown in a bounded, offline worker. The next user outcome is a readable
static equation or diagram in that same Finder window. Each failed item must
leave its own authored source visible without blanking the rest of the file.
The containing editor stays closed. This unit does not change live Preview,
HTML/PDF export, document bytes, or the final signed-install gate.

## Current source and reconciliation

Implementation starts from main `8f5e47ac` plus the reviewed Quick Look GFM
candidate `6e0edc78`; the latter is still under exact-head CI and Finder
qualification. The source compatibility candidate is separate. `QuickLookSource`
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
stricter URL mode permits only internal fragments and validated embedded
raster images in generated markup; authored Markdown URLs remain blank.
Per-item and aggregate generated-byte admission occurs before the sanitizer
copies a fragment, and a refused item leaves its own source visible. These
1 MiB/4 MiB caps are provisional pending Release renderer measurements.

Four focused package cases pass for accepted plus stale items, out-of-range
rejection, generated URL/script neutralization and an oversized item followed
by a valid one. The existing sanitizer and derived-content suites pass 3/3
and 10/10. This candidate has no producer or worker caller, and establishes
neither real static math/diagrams nor Finder behavior. It remains local until
the preceding GFM and encoding PRs converge and its own exact-head CI review
is complete.

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
no HTML; its source remains in the GFM body. A process-wide timeout is still
allowed to return no reply, never partial bytes. Do not increase the existing
three/four-second deadlines on a guessed performance claim. If complete
technical rendering cannot fit, record the measured counterexample and
revise the architecture before implementation. Renderer completion, XPC
reply and child exit each settle once; late callbacks after cancellation or
teardown cannot publish another generation.

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
