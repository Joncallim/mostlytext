# Bound non-cancelled regex searches

## Owner summary

A regular expression can consume a search worker indefinitely when its input
causes repeated backtracking. Cancelling Find already stops such work, but a
query left open keeps running. This change gives regex matching a finite
execution budget, reports an incomplete search plainly, and prevents a
partial Folder Search from authorizing Replace All. Literal search and the
existing selected-result/open behavior stay as they are.

## Baseline and scope

Main `4b7ec88f16535b0d0d52d8a50ea98b6c84d0b08f` already uses ICU progress
callbacks to honor task cancellation and already retires a closed Find bar's
search. The missing case is an active, non-cancelled pathological pattern.
A standalone optimized Foundation/ICU run of `(x+x+)+y` against 40 `x` units
and `!`, using the current `.reportProgress` option but no cancellation, was
still running when killed by an external two-second deadline. Folder Search
currently collapses a matcher error to `[]`, which would falsely present a
timed-out file as searched if the matcher began reporting deadlines.

## Implementation contract

- `TextSearch` owns the regex budget. Each regex match call gets a two-second
  monotonic deadline; literal matching is unaffected. Cancellation wins if
  cancellation and expiry coincide. ICU progress callbacks may stop the work
  when the deadline passes, and partial matches are discarded with a distinct
  `timedOut` error. This is a practical callback-based budget, not a claim
  that Foundation guarantees a hard wall-clock interruption inside every
  regex or pattern compilation.
- Folder Search has a ten-second total operation deadline in addition to the
  per-file regex limit, beginning before query validation and index lookup.
  It reports timeout separately from completion,
  truncation, cancellation, invalid pattern and index failure. Previously
  streamed rows may remain inspectable, but Replace All remains disabled
  unless the entire search completed. The status must say results are
  incomplete, even when there are no rows.
- The current-document Find model surfaces a localized timeout diagnostic,
  clears stale matches and does not publish a partial result. Its existing
  generation and close-cancellation guards remain authoritative.
- The existing app and package ownership/dependency directions remain
  unchanged. No external process, network path or new search engine is added.

## Verification and limits

The same non-cancelled pathological pattern now returns `.timedOut` after
about two seconds in the matcher and Find model. A two-file folder fixture
keeps an earlier streamed match but returns `.timedOut` rather than
`.completed`; a test-only zero whole-search budget proves the second deadline
path without delaying the suite. A model-level app test checks that timed-out
rows cannot authorize Replace All and that skipped-file count remains visible.

Corrected-source package selections passed **134 tests in 16 suites** in Debug and
optimized Release. They cover ordinary regex/literal matching, cancellation,
CRLF, match limits, Find identity/domain and the new timeout paths. The
independent diff review found that the first implementation started the
whole-folder budget after regex validation; it now starts before validation,
returns an explicit timeout at that boundary and preserves literal search
outside the regex-only budget. The first
focused Debug run failed only because its new test assumed directory enumeration
order; the corrected test seeds a fixed index order and the original failure
remains in `/private/tmp/mostlytext-regex-focused-debug.log` (SHA-256
`168b6e376f913ffb9064bd6cd853890965c48bb2779f5823b4f4ead8756f1afa`).
Corrected Debug and Release logs are `/private/tmp/mostlytext-regex-corrected-debug.log`
(`927d65641e0ee71a52a47807446a68cd13814e6286c78fc3b48f17fd882043f0`)
and `/private/tmp/mostlytext-regex-corrected-release.log`
(`f0bfb6038f16d69ce01e2edd26b15a8b01087f606840ee7e82150cc8421d6351`). Strict SwiftLint,
SwiftFormat, catalog structure (747 entries across 15 catalogs) and ordinary
source compliance pass. A local Release app build passed before the last
package-only test seam was added; the final-source hosted app build and model
test remain to be recorded. Strict release compliance still has ten existing
#14 source/rights/publication failures.

The protected native checkpoint, #17's broader native journeys and a strict
hard interruption guarantee remain separate acceptance work. Foundation does
not promise that every regex compilation or long-running engine operation
will call the progress handler promptly enough for an absolute deadline.
