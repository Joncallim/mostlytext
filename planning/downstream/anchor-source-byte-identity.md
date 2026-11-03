# Bind heading analysis to the exact parsed source bytes

## Owner outcome and baseline

A heading index must not assign a new source digest to a parse of a different
byte sequence. Baseline is #575 head 385dc2fa; integration remains cf3f8b86 and
master remains 15c0fae2. This is a bounded #117/#183 identity correction, not
activation or acceptance of linked TOC or native navigation.

## Binding source change

HeadingAnchorIndex checks SourceMap geometry and compares body/front-matter
Strings. Swift's canonical-equivalence equality accepts, for example, U+212B
and U+00C5 despite different UTF-8 bytes and identical UTF-16 geometry. The
result then claims a digest of the supplied source even though its parse came
from another sequence. Exact body/YAML comparisons alone are also insufficient:
extraction drops delimiter spelling and trailing whitespace. A `---` to `...`
closer change can have identical geometry and extracted fields.

Revised binding before implementation: MarkdownDocument carries an optional
sourceSHA256 value. ParseEngine supplies it from the complete immutable input
on its existing parse worker. Keep the public initializer source compatible with
a nil default for manually constructed models; an unbound model cannot mint an
anchor identity. HeadingAnchorIndex hashes the supplied complete source once,
requires equality with the parse-bound fingerprint and reuses that digest for
its identity. Preserve exact UTF-8 body/raw-YAML and existing structural, offset,
revision and policy checks. No consumer may reconstruct the fingerprint from
the lossy body/front-matter fields. This is a model-consistency check, not a
cryptographic producer signature or trust grant to arbitrary external models.
Fingerprinting runs on the existing parse worker, uses contiguous UTF-8 when
available and otherwise a 64-KiB scratch buffer; it allocates no second complete
source Data. It adds one linear pass to parsing. The index reuses its already
required digest rather than hashing the supplied source twice.
Emitted-heading analysis retains its
existing separate source/rendered digest gates and remains outside this unit.

No dependency, allocator policy, raw-HTML admission, native route or output
activation changes. The optional model metadata is the only interface addition.
Exact-byte-equivalent inputs remain valid;
canonically equivalent text parsed independently still works, with distinct
source identities. Nil and present-empty front matter remain distinct.

## Discriminating controls and merge gate

Use the real pinned ParseEngine. Pair same-geometry canonically equivalent body
and front-matter inputs, assert equal Swift values but unequal UTF-8, and require
sourceDoesNotMatchParse. Also reject same-geometry delimiter/whitespace changes
and models without a parse fingerprint. The unchanged helper must fail the
Unicode cases; the body/YAML-only intermediate must fail delimiter cases.
Positive controls parse/index each spelling independently and preserve original
body bytes/different digests. Retain existing index, offset and lifetime tests.
Run source-bound non-application Debug/Release tests, strict lint/pinned format,
Compliance and unsigned app/UI-target build-for-testing only. Complete exact-head
hosted validation and merge-tree proof remain required before integration.

No local app/app-target execution, owner-store change, native acceptance,
Daybreak/test account, signing, master/public promotion or publication. Shared
DOM inventory, collision-safe output/links and actual browser/native navigation
remain separate #117 gates.

## Executed evidence — 3 November 2026

The original helper fails both actual Unicode body/front-matter cases. The
intermediate body/YAML-only guard fails both delimiter/whitespace cases; the
architecture was revised before adding model fingerprint metadata. These
failing runs are retained, not reclassified as passes.

All 133 tests/18 suites of the complete pure MarkdownEngine test module pass
Debug and Release, including native/bridged Unicode and chunk boundaries,
standard hash vectors, independently parsed spellings, delimiter differences
and refusal of unbound manual models. All 34 source/test files are copied
unchanged with no import adaptations or stubs. Pinned cmark/Markdown/Yams
revisions remain unchanged. Existing parser timing tests are documentation
ceilings, not final product performance-budget acceptance.

Strict lint, SwiftFormat 0.63.1, 99 Compliance controls and final inventory pass.
The project was regenerated/pinned after the new source/test files; unsigned
app/UI-target build-for-testing passes with no new warning text and no execution.
The optimized warm fingerprint component has three retained samples per case:
native medians 0.420 ms at 1,048,585 bytes and 3.837 ms at 10,485,769 bytes;
bridged medians 0.403/3.824 ms. All outputs equal the digest oracle. This is not
a full parse, peak-memory, cold/native or final budget claim. Driver/results are
in evidence/anchor-source-identity-2026-11-03; original logs and source manifest
remain in the external closure-review-20261102 directory.

Full exact-head hosted validation and actual merge-tree proof remain required.
Review here is scoped self-review, not independent final #115 acceptance.
