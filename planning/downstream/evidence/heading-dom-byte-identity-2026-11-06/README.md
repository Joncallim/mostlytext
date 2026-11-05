# Exact heading identifier evidence

Baseline main05238f4, identical staged heading helpers on PR93candidate03fc4607.
The actual new allocator regression fails against unchanged production source: a
decomposed authored ID wrongly causes composed café to become café-1. The first
standalone manifest omitted the deployment platform and failed availability
compilation; that setup log is retained separately. With macOS26declared, the
real behavioral before-failure is retained. Exact source then passes4allocator
tests Debug/Release, and11allocator/index tests Debug/Release using the complete
49file MarkdownEngine source/test fixture. No import adaptation or source stubs.

The broader182test/25suite Foundation Debug run fails its existing10MB parse
ceiling:68.269s against60s, while actual complete package compilation also runs.
This is a retained timing failure, not a full-suite pass or a changed threshold.
Only the affected heading suites are rerun separately; complete hosted CI remains
required. The allocation correction does not change the parser or its benchmark.

Actual package build-tests and real app/UI build-for-testing compile successfully
without executing native code locally. New actual DOM tests cover entity-decoded
decomposed IDs and legacy names beside a composed generated target, both authored
spellings in the inventory, byte-preserved markup, and refusal of an actual exact
collision. Hosted execution is required before merge. Existing SVG/DOM budgets
and ordinary output policy remain. The first enlarged test type hit the250line
limit; new cases moved into an extension without altering assertions. Pinned
format and strict lint pass1442files; ordinary compliance passes0unverified.

Review was a scoped implementation-agent review of Unicode ID semantics, actual
source/render markers, duplicate/collision refusal, memory/work bounds and source
compatibility. It is not independent final compliance/release or native acceptance.
No dependency pin, notices or SBOM changes; no local app/CLI/helper/native test
execution. This remains the staged anchor machinery: TOC links are not activated.
