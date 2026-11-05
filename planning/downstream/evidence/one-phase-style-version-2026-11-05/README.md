# Reject obsolete style results at the actual one-phase boundary

Unmodified TokenSystemValidatorab93bca checks content ownership only before
calling a provider. A controlled continuation changes the content version while
the provider is suspended; synchronous provider reentry changes it before return.
In both cases the actual validator calls the style interface with obsolete
results and returns success. Twenty-four assertions fail over shrunk, grown and
same-length text, with both apply and replace actions. Unchanged-content and
already-obsolete controls pass, so the test does not merely suppress all styles.

Owner Neoncd14f22ae8f8402b175a0bafd87560b78c7549e9 adds a version equality guard
immediately after each provider result and before the style interface is called.
Existing Validation.stale reports lost ownership. No API, scheduling, action,
semantic/paint range, buffer or parser/grammar change occurs. Original BSD text
and every previous repair remain unchanged. Only the Neon application pin changes
relative to mainf87a414a, with23 other pins unchanged.

Forty-six Foundation/C functions in13 suites plus8 XCTest cases pass Debug and
Release after the correction, including all earlier client/style/buffer/range
and2,000-edit fresh-inline controls. Actual class, protocol, Token and test bytes
are verified against the immutable owner/application source; this is the real
validator calling a recording interface, not a mock that discards stale results.
No AppKit/SwiftUI/WebKit/product code executes locally. The real HighlightingTests
target compiles with forced locked resolution. All316 Compliance controls,
inventory, full pinned format and strict lint pass. Full exact-head hosted
package/app/CLI integration is still required before adoption.

The first fixture compile crashes the Swift6.3.3 compiler while lowering a
reabstraction thunk for the generic default sync closure. An explicit nil sync
closure avoids that compiler defect without changing compiler/language mode,
provider contract, assertions, actors or deadlines. The compile crash and the
actual24-assertion runtime baseline are retained separately; only the latter is
a demonstrated validator defect. Tests coordinate actual suspension with a
continuation/stream, without sleeps. Native abort/lifecycle/IME/Release stress,
full-editor performance and final acceptance remain separate issue criteria.
