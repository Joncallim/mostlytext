# Validated raw-body rendering — 5 November 2026

An opaque immutable value now carries the actual parser's accepted equation body
and explicit limits into the existing native renderer. The legacy String API
keeps automatic delimiter detection. Body mode does not strip delimiters again,
and cache keys include mode, limits and exact UTF-8 bytes. Source occurrence UUIDs
remain separate from renderer identity. Metrics, layout and Canvas drawing use
the same input; Textual adds a typed factory over its existing attachment.
No second renderer, source write, remote service or accessibility claim is added.

The inspected Foundation fixture passes **140 tests / six suites in Debug and
Release**, including the existing 100,000-case partial-input corpus. Eight new
functions cover exact source/limits, invalid/resource/configuration categories,
canonical-equivalent but byte-distinct cache keys, raw versus automatic mode,
repeated parsing, cancellation, released values after eviction and replacement at
capacity. All 28 source/test files match immutable owner blobs; only the unused
outer SwiftUI View namespace is replaced with an empty public enum. No fonts,
SwiftUI/AppKit/WebKit, product, CLI, owner documents or signing keys execute locally.

Cache retention preserves the original automatic NSCache eviction and adds a
lock-owned conservative admission upper bound: at most 512 atom and 1,024 display
entries. Before admitting an absent key at capacity, clear storage and reset the
bound. Early automatic eviction only makes accounting conservative; no separate
key registry retains source after eviction. Reference ownership keeps storage and
accounting together. The initial unqualified dictionary helper and cache controls
are retained alongside their passing logs; replacing NSCache would have lost its
memory-pressure behavior. Final pressure-preserving Debug/Release logs each pass
140 tests. Weak-reference controls measure retained values after 1,000 admissions,
and returned hits must never contain stale values. Original parser/token assertions
remain unchanged. Exact resident bytes, peak graphics allocations and a graphics
execution deadline are not claimed. The original real 100-equation renderer
benchmark remains unchanged and must pass hosted CI.

The actual locked MathRenderingTests target compiles locally, including the five
new native functions. The first compile fails only because a test constructs
Textual's internal environment initializer through an ordinary import. The existing
Preview-test precedent uses @testable import Textual; applying that to this test
preserves all assertions and changes no dependency API. The corrected compile
passes in 7.07 seconds on the first child; the final pressure-preserving
engine target compiles in 16.76 seconds and PreviewTests in 6.25 seconds. Actual engine/Textual modules compile without diagnostics.
Hosted execution must verify mode/cache isolation in both warm-up orders, native
comment metrics, repeated/distinct occurrence identity, actual rendered image,
legacy display compatibility and cancellation of a warm body cache.

All 330 Compliance controls, full inventory, pinned format and strict lint pass.
Notices/SBOM identify the actual owner changes. Only the two matching engine and
Textual pins change among 24, relative to the prepared PR87 head. Original engine
fonts, licences, snapshots/tests and 94 unrelated original files remain exact;
three original source files differ from upstream after the combined parser and
body-rendering work. Relative to PR87's Textual owner, only the manifest and two
math factory/attachment files change. Owner patches and original-file hashes are
retained. Fresh owned bare mirrors reuse verified Git objects without modifying
prior workspaces or global caches; new immutable owner objects are fetched only
into this scratch directory.

manifest.json records all exact source/test hashes and each raw log's size and
SHA-256. reproduce-foundation.py reconstructs only the permitted Foundation files
from an exact local engine clone into a new directory, checking every digest.
Run swift test and swift test -c release there. No native renderer is included in
that executable fixture; real native module/test evidence comes separately.

This slice is dependent on PR87 and remains unmerged until fresh full hosted CI,
exact review and verified integration pass. Joint production Preview/Export
activation, source-anchored localized diagnostics, physical workers/cache policy,
reference-link identity and equation accessibility/navigation remain open in #9.
Textual renders attachment bodies as Canvas symbols, so a label on MathView alone
cannot establish accessible paragraph children; a focused hosted accessibility
probe is required. Final native visual/VoiceOver and exact-artifact gates stay held.

The named accessibility architecture probe compares a labeled actual math
attachment outside and inside the full InlineText/Canvas path. Same-process
positive controls must expose standalone equation and both ordinary paragraph
neighbors before its observation is accepted. It records the actual inline-label
result; it does not assert either unknown answer or claim final VoiceOver. Tree
traversal/asynchronous layout readiness are bounded and the owned synthetic window closes after
the probe. It compiles locally but executes only hosted. The initial
compile's ambiguous Testing.Attachment/Textual.Attachment protocol lookup is
retained; explicit Textual qualification fixes setup without changing assertions
or production source. A later JSON Data-to-String lint error is corrected with
a checked UTF-8 conversion, retaining that failed lint log. The readiness loop
yields MainActor with the same 50 checks/10 ms bound; no nested RunLoop blocks
SwiftUI state updates. Empty/failed positive controls remain a real setup failure,
never evidence that inline equations are absent.
