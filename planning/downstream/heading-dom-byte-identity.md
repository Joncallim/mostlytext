# Preserve exact authored heading identifiers

## Owner outcome and current baseline

A generated heading should reserve the identifier that the browser actually
matches. An authored decomposed Unicode identifier must not steal the composed
identifier allocated for a Markdown heading. Both authored spellings must survive
inventory when they occur together. This corrects the staged #10 anchor machinery;
linked TOCs and native heading navigation remain disabled in this unit.

The source baseline is main05238f47191e8350f4ace5817a5f6066e1394176, with the
unchanged heading helpers also present on PR93 candidate03fc4607. The existing
allocator and emitted DOM inspector use Set<String> for exact decoded IDs. Swift
String equality collapses canonical Unicode equivalents; HTML identifier matching
does not normalize them. See the [Swift String documentation](https://developer.apple.com/documentation/swift/string)
and [HTML fragment selection](https://html.spec.whatwg.org/multipage/browsing-the-web.html#the-indicated-part-of-the-document).
The separate exact source-fingerprint guard remains unchanged.

## Binding correction and interfaces

Keep authored decoded identifiers as their original ordered String values in the
bounded DOM inventory; preserve duplicate occurrences and canonical variants.
Use UTF-8 byte keys for reservation, generated-target membership and final target
position maps. Do not normalize authored identifiers. Generated bases retain the
existing NFC/lowercase policy, duplicate suffixes and256byte ceiling.

Allocator and index reservation inputs accept a sequence of strings rather than
requiring callers to first collapse them into a Set<String>. Existing set/array
call sites remain source compatible, and the allocator keeps a no-argument
initializer. The internal emitted inspection returns its bounded array of decoded
values. No new module dependency, raw-HTML policy or production route is added.
All existing8MiB/4096explicit-ID bounds and marker/source/render identity checks
remain. The correction neither serializes the DOM nor rewrites authored markup.

## Test and review boundary

First run a decomposed authored reservation against the old allocator and require
its incorrect suffixed result to fail. Cover composed reservation, both decoded
spellings, entity-decoded IDs and legacy named anchors. Actual emitted-DOM tests
must publish a composed generated heading beside a distinct decomposed authored
ID, preserve the authored bytes and retain both inventory entries. A true exact
collision must still reject an incorrectly allocated target. Run inspected pure
Foundation/C/CryptoKit/HTML-parser controls in Debug/Release, compile actual target
tests without local native execution, and require hosted CI before merge. Review
Unicode semantics, collision refusal, work bounds and ordinary-output preservation
separately. Owner native/signing, full TOC activation and independent final release
review remain separate gates.

## Verification checkpoint

See [the exact source/log packet](evidence/heading-dom-byte-identity-2026-11-06/README.md). The real before-failure, affected Debug/Release passes and separate retained broad parser timing failure are recorded. Actual native bundles compile only locally; hosted execution is the merge prerequisite. The allocator policy version stays1because this repairs the existing exact-authored-ID contract without changing generated-base normalization.
