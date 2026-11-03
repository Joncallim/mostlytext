# Enumerate height-estimation paragraphs without per-unit Objective-C calls

## Owner outcome and baseline

Keep large-document height estimates responsive without changing wrapping,
paragraph boundaries, font metrics or the existing two-second regression limit.
Master is 87d8d48b; the source baseline is 030a4ff0. The unchanged package source
in Intel run 41557163319 takes 2.66097 seconds in the huge-document estimate,
failing its existing limit. The ARM package suite passes; preserve both results.

## Binding source scope

The meter first finds every paragraph by calling NSString.character(at:) for
every UTF-16 unit, then the estimator scans each paragraph again. Replace only
the first pass with a pure Foundation scanner reading at most 16,384 raw UTF-16
units (32 KiB) at once. Preserve exactly LF, CR, U+2029, CRLF as one terminator,
and the empty final paragraph, including across chunk boundaries. Do not copy the entire
document, broaden the separator set or change measurement/cache/estimate math.

Keep ContentHeightMeter.forEachParagraph as the existing app/test adapter and
delegate it to the small pure scanner. Test empty/trailing/mixed separators,
Unicode and malformed UTF-16 against the exact old loop. Measure both scanners
with the original huge fixture in Debug/Release in a Foundation-only harness.
The full native-font height assertion and all other package tests must execute
in complete hosted qualification. No local AppKit/product/UI test is run.

This is scan-cost reduction, not incremental tree-sitter repair, a new height
approximation, final Release keystroke calibration or #203 acceptance.

The first CharacterSet/rangeOfCharacter prototype failed the actual malformed
UTF-16 comparison corpus by skipping separators after unpaired surrogates.
That failed experiment is retained and rejected. The bounded raw-unit scanner
must pass the unchanged 10,000 comparisons plus cross-chunk CRLF/surrogate cases.

## Focused verification

Four raw-coordinate cases pass in Debug and Release, including 10,000 old-loop
comparisons and chunk edges. The rejected CharacterSet prototype is retained
with its actual malformed-UTF-16 assertion failures. On the original 130,000-line
fixture (5,478,889 UTF-16 units), four-sample Foundation-only medians are:

debug: legacy-scan 59.74ms, bulk-scan 48.40ms, legacy-with-estimate 282.13ms, bulk-with-estimate 253.38ms.
release: legacy-scan 45.72ms, bulk-scan 29.85ms, legacy-with-estimate 116.57ms, bulk-with-estimate 99.87ms.

The estimate benchmark uses the exact estimator body with an explicit fixed
font-metric initializer adapter; it does not run native font measurement or
establish the unchanged full-height two-second assertion. Checksums agree.
Complete hosted execution remains required before integration.
