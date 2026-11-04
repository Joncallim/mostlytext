# Reject malformed Replace in Folder ranges before arithmetic

## Owner outcome

A malformed folder replacement plan must be skipped without crashing or changing
its file; processing of later valid files must continue. The existing plan
contract already promises this. Complete native folder-search/replace acceptance
remains in MostlyText #6/#17; this unit proves the Foundation-only plan and disk
engine behavior without launching the app or using a separate account.

## Baseline and reconciliation

Start at main `17b1e7a011ff0724fa480ce4fc2290a245b033bd`. The current
`TextSearch/ReplacementPlan.swift` rejects missing, unordered, overlapping and
ordinary out-of-bounds ranges, but computes `NSMaxRange` before establishing that
length is nonnegative and the sum fits. `SearchMatch` has a public unchecked
`NSRange` initializer. A negative length can reach Foundation replacement;
large endpoints can overflow in validation. Existing safety tests cover neither
case. Do not change the public match model or infer a native user trigger.

## Contract and ownership

Only `ReplacementPlan.applying(to:)` changes production behavior. Validate each
range in order: a real nonnegative location at or after the previous end, a
nonnegative length, location no later than the UTF-16 buffer end, and length no
greater than buffer length minus location. Only after those bounds may the end
be added. Validate every match before adapting line endings or splicing text.
Keep empty plans, zero-width matches at valid boundaries, adjacent matches,
UTF-16 coordinates and literal/line-ending-preserving replacement semantics.
No encoding, source-revision, protection, cancellation, write-authority or
conditional-publication change is authorized.

The existing engine calls this method before preview line calculations and
before publication. Bad plans keep preview's changed-since-search result and
replacement's skipped-cannot-represent result. No new UI string, API, module
relationship, filesystem authority or stored representation is introduced.
The algorithm stays linear in the number of matches with constant validation
storage. No native rendering, accessibility, localization or export change.

## Regression and completion sequence

1. Add deterministic Swift Testing cases with negative locations/lengths,
   Int.min/Int.max, overflowing endpoints, one-past-end and a valid prefix
   followed by malformed range. Preserve ordinary invalid-order/overlap tests.
   Run actual old source in an owned Foundation/Darwin source-identical fixture;
   retain its original failure/termination before fixing production code.
2. Add positive boundary/Unicode/CRLF controls and prove preview refusal,
   unchanged original file bytes and continuation to a subsequent valid file.
3. Implement only the checked subtraction-before-addition validation. Run the
   complete TextSearch fixture suite in Debug and Release; bind every copied
   source/resource/test byte and keep native/app targets out of local execution.
4. Run strict lint/pinned format, Compliance and complete hosted macOS checks,
   including the locked Release app/CLI build and non-UI app suite. Merge only
   the qualified head and verify actual merge tree/parents. Update the owning
   issue checklists with this specific result; do not check the entire native
   folder-replace or final audit criterion from a source fixture.

Stop and reconcile before changing any additional product behavior, source
binding, authority or native gate. Final whole-app and exact release acceptance
remain outside this bounded range-validation fix.

## Actual failing-before result

The source-identical owned fixture compiled all three Foundation/Darwin modules
and the complete existing TextSearch test corpus. Separate filtered runs of the
new overflowing-end and negative-length controls both terminate the old test
host with an uncaught `NSInvalidArgumentException` from
`NSString.stringByReplacingCharactersInRange`. The captured overflow case passes
the old endpoint comparison and reaches replacement; no Swift arithmetic-trap
claim is needed. Preserve both original logs. The subtraction-before-addition
contract above rejects both cases before either endpoint arithmetic or
Foundation replacement. No application/AppKit/WebKit target was run.

## Source qualification

All 131 TextSearch tests /20 suites pass in both Debug and Release on exact
copied source/resources/tests, including five new methods. The 86-file
[source manifest](evidence/replacement-plan-range-bounds-2026-11-04/source-files.json)
and [validation receipt](evidence/replacement-plan-range-bounds-2026-11-04/validation.json)
record both actual old-source Foundation crashes, final file hashes, toolchain,
commands' retained log hashes and native limitations. No imports, source or
resources are substituted. The independent fixture manifest is retained beside
the receipt so another Foundation-only run can use the same module graph.

Strict lint is clean and pinned SwiftFormat0.63.1 passes. Initial new-test tuple
and collection-layout lint findings were corrected without changing assertions;
those initial logs remain retained. All257 Compliance tests and the source
inventory pass. Complete hosted locked builds/tests and exact merge proof are
required next; local source evidence does not establish mounted-app acceptance.
