# Buffered repaint coordinate evidence

Current semantic-token/paint-range correction: [semantic-paint-boundary](semantic-paint-boundary/README.md).

The first hosted failure and current combined correction are recorded in
[hosted-remediation](hosted-remediation/README.md). The original evidence below
remains the first implementation record.

Neon d58b074a067861161a1df6d5b42d700526d0e7dc adds the package-only dirty-range
edit hook and calls it before the client publishes new edit invalidations. The
original BSD licence, parser pin and grammar bytes are unchanged. Only Neon
changes among 24 locked dependencies; verification.json records the graph.

The original class plus LegacyBufferNotificationShim.swift models the missing
old notification hook. baseline-missing-notification.log records two concrete
wrong-coordinate failures. This is a labeled missing-hook model, not an executed
old TextViewHighlighter. original-buffer.swift preserves the actual base class;
neon-buffer.patch records the separate production hook and adapter call order.

candidate-all-debug.log and candidate-all-release.log pass 37 Swift Testing
functions in nine suites plus eight existing XCTest cases. One new function
checks 75,772 edit/dirty-set cases against an independent per-character oracle.
Other cases cover deletion-tail survival, successive edits, nested depth, idle
and all-document states, sparse coordinates and reentrant scope ownership. All
prior client controls and the unchanged thousand-edit/query stress test pass.
fixture-inputs.json hashes the complete copied Foundation/C inputs. Runtime
RangeState and TreeSitterClient source bytes match the pinned owner fork. The
existing Rearrange AppKit/UIKit helpers remain excluded. No local Neon/text-view,
app, AppKit, SwiftUI or WebKit code executes. The full real HighlightingTests
target compiles with forced locked resolution, including the strict real
text-view typing/deletion control; hosted execution is still required.

The first 316-control compliance run caught a stale generated SBOM because the
suite started before generation finished. Its exact failure is retained as
application-compliance-tests.log. After resolution and generation completed,
application-source-check.log passes and all 316 controls pass in
application-compliance-after-sbom.log. Pinned formatting and strict lint pass.
The first generator command had a Python indentation error before any mutation;
it was corrected before resolution. No failed result is described as passing.

The adapter's strict hosted comparison must pass before adoption. This does not
activate widened edits, raise the 8192-unit fallback, prove whole-editor latency
or complete native/signing/release acceptance. All six release-only attribution
and source-publication predicates remain separate. Architecture:
../../buffered-repaint-coordinate-repair.md.
