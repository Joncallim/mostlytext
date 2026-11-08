# Check included-range lookahead before reusing Markdown tokens

## Owner summary and ready baseline

The parser dependency must respect the bytes a caller actually supplies and
produce the same tree when a parsing range changes as it does from a fresh
parse. Two narrow upstream corrections are candidates: one checks a token's
lookahead before reusing it, and the other prevents the UTF-16 decoder from
reading beyond the caller's advertised chunk. The current app forces fresh
parses for Markdown inline, so the reproduced C reuse mismatch is not evidence
of an editor-visible Markdown inline defect. Neither correction establishes the
whole-document 50 ms requirement or explains the original Debug abort.

Baseline main is `a46c57c4b62376b67492cf67421a4961fdf55c1c`. PR146's independent
inline styling candidate `024103b3` remains frozen with seventeen first workflows
in progress. This branch must not merge or change that candidate while its firsts
are incomplete. Read AGENTS.md, EPIC_STANDARD.md and RELEASE_HARDENING.md; preserve
all accepted source, identity, geometry, scanner-safety and shared-runtime work.

## Existing source and primary evidence

The active runtime is `3b1fb00f8c4f8907073f9b7342a807a0231867fa`. Its
`ts_parser__reuse_node` tests included-range differences against only the token's
own end byte. The maintained scanner backport and current wrapper range-replacement
repairs solve different defects. Confirm exact live pins and wrapper behavior
before claiming application reachability; component reproduction is not an
observed native editor failure.

Upstream [issue5636](https://github.com/tree-sitter/tree-sitter/issues/5636) reports
incremental/fresh Markdown-inline disagreement. The reviewed
[fix5641](https://github.com/tree-sitter/tree-sitter/pull/5641), merged as
`15ddfb21edb11831e34d666110b8efe3aa081f9b`, includes a token's lookahead extent in
that range check, preserving the existing EOF sentinel. It was also backported
to release-0.26 in [5656](https://github.com/tree-sitter/tree-sitter/pull/5656).
Do not upgrade the runtime or grammar wholesale or relax fragile-node safety.

## Named pre-implementation question

Does the exact current C runtime reproduce stale code-span structure with the
actual vendored Markdown-inline grammar when an included range expands, and does
only the exact upstream guard correct it? Require failing-before evidence before
shipping any patch. Keep unchanged-range, shrink, prefix/position, UTF-8 and
UTF-16 little-endian controls, and compare incremental trees with fresh trees.
If the actual grammar does not reproduce, retain the result and stop adoption;
do not manufacture a different application failure or infer a performance fix.

## Ownership and interfaces

Use the existing runtime public C API and current vendored grammar in a standalone
console driver. It owns generated fixture bytes and parser/tree lifetimes only.
The existing parser API/ABI, wrapper interfaces, edit geometry, source bytes,
range policy, query capture names, public modules and application behavior remain
unchanged. No new package or dependency is introduced by the probe.

## Invariants, data flow and failure handling

For each fixed fixture, parse the narrow included range; retain the old tree;
expand or shrink to the intended range, reparse incrementally, and compare to a
fresh parser over the exact same input/ranges/encoding. Capture the full ordered
node symbol/named/error/missing/extra/byte/point/depth facts, not a timing badge.
UTF-16 byte offsets and columns use two bytes per code unit. Keep all trees live
until comparison, check every allocation/API result and free every owned value.
The first driver records differences without pretending they pass. A shipping
regression must require equality after the guard correction. No assertion,
fixture byte, deadline or resource policy changes to turn a failure green.

## Trust, execution and resource budgets

Local execution is limited to an inspected pure-C console linked only to normal
system C libraries. Inspect actual linkage before running; no AppKit, SwiftUI,
WebKit, CoreText, graphics, JSC, Node, WebAssembly or product runtime. Read only
reviewed pinned source and generated small fixtures; no owner documents, account
preferences, GUI, entitlement, signing or release activity. Compile commands,
all source hashes, actual binary hash/linkage, full stdout/stderr and bounded
process outcome are retained. Start with tiny fixed cases and a 10-second
external process bound. Sanitizers remain required; a timeout or crash is failure.

No performance claim follows. The original 50/400/500 ms gates and 8,192-unit
large-document fallback remain. This correctness fix may deliberately reparse
more text when the old cache is invalid. Accessibility, localization and durable
formats have no new UI/string/encoding policy; existing native checks remain.

## Adoption boundaries and slices

1. Commit this architecture before code. Validate current immutable source and
   inspect standalone linkage. Retain original exact C reproduction/control data.
2. Only if reproduced, compare a source copy with the exact upstream guard change;
   preserve EOF and every other runtime byte. Require all fixed cases and actual
   grammar/query/ownership/sanitizer controls, including existing C comparisons.
3. Before dependency publication, record the precise selected source delta,
   provenance/license preservation and coherent runtime/wrapper/Neon/vendored
   manifest update architecture. Current PR146 must qualify/merge before this
   branch changes main. Resolve an exact new graph through the authorized hosted
   path, preserving unrelated revisions including the qualified inline fix.
4. Qualify complete app/package, real wrapper/native editor/theme, original
   geometry/fresh-parse regressions and exact integration identity before merge.
   Update canonical owning issues only for proved scoped behavior.

## Stop conditions and definition of done

Stop for missing reproduction, changed semantics/ABI/ownership, unexpected input,
source drift, new warnings, native failure or a need to weaken existing controls.
Do not discard first outcomes or retry unchanged functional failures. Record
ordinary local choices in this architecture rather than silently expand it.
The probe alone is not production completion, native acceptance, performance
repair, independent rights approval or release readiness. Broad issues stay open
until their separate original criteria are fulfilled.

## UTF-16 decoder boundary: additional named pre-implementation slice

Source review after the first lookahead probes found a second independent error
in the exact pinned runtime `3b1fb00f8c4f8907073f9b7342a807a0231867fa`.
`lib/src/unicode.h` passes a byte count to the `U16_NEXT_LE/BE` macros, which
index 16-bit code units. When a lead surrogate ends the callback's declared
two-byte chunk, the macro can inspect a following unit outside that chunk.
The maintained upstream [fix 5549](https://github.com/tree-sitter/tree-sitter/pull/5549)
was merged as `e4ac513afd85a7fe1015abc0ef46a4148aa7baf6`. It first rejects
chunks shorter than two bytes, then passes `length / 2` into both macros.
This is an exact-source candidate, not authority to upgrade the runtime.

The exact SwiftTreeSitter `76f93e7e325dcd05561a13ed63bcc92cb85be8da`
`Input` API permits a caller-supplied `ReadBlock` that returns arbitrary `Data`
and advertises its exact byte length to the C parser. The normal Neon editor
path instead builds a snapshot from `String` and extracts valid Swift character
ranges. Thus a two-byte lead-surrogate callback is a supported C/wrapper API
boundary, but no current editor journey has been shown to produce it. Keep this
component scope explicit. The separate Swift string-reader behavior near a
1,024-unit surrogate boundary is only a source hypothesis and requires its own
reproduction; do not fold it into this C correction or infer a user failure.

### Question and test contract

Before changing any dependency code, use a reviewed standalone pure-C console
which includes the exact pinned internal `unicode.h`. Give each decoder a
declared chunk length of 0, 1, 2 and 4 bytes. The principal two-byte case is a
lead surrogate with an adjacent fake trail surrogate in allocated memory but
*outside* the declared chunk; compare both little- and big-endian results.
Include valid basic-multilingual-plane, valid surrogate-pair, and ordinary
two-byte controls. Record actual decoded code point, bytes consumed, declared
length, and whether the outside sentinel was mistakenly combined. Require the
original runtime to report failures honestly, with complete stdout/stderr and
nonzero exit. An instrumented original build must additionally use a truly
two-byte allocation to expose an over-read under AddressSanitizer; preserve
that first crash and diagnostics rather than hiding it behind a poison buffer.
If no over-read or incorrect decoded value reproduces, stop this slice.

After preserving complete original outcomes, apply only the two decoder guards
and byte-to-code-unit corrections from upstream 5549 in a *new isolated source
copy*. Use the same unmodified fixtures and acceptance predicates, plus
AddressSanitizer and UndefinedBehaviorSanitizer. Require zero detector findings,
correct declared-boundary behavior, and the same valid-control results. Check
all other runtime bytes, public headers, exported symbols, existing 324-pair
subtree corpus and eight-case lookahead corpus before considering publication.
Do not claim LeakSanitizer if it was not run.

The diagnostic and its isolated candidate may read only reviewed dependency
source and generated fixed bytes. Inspect final binary linkage before any
execution. There is no app, Swift package, GUI, JavaScript, document or owner
data access in this slice. Bound each run to ten seconds. Preserve compiler
command, source and binary hashes, linkage, complete stdout/stderr, actual exit
status and sanitizer settings. No test waiver, deadline extension or product
source edit follows from this finding.

Before *any* dependency publication, amend the adoption architecture to cover
the actual combined delta, license and attribution, manifest graph, hosted
resolution and fresh app qualification. Keep PR146's published firsts frozen.

### Original result and separate big-endian pair defect

The first exact-runtime matrix and sanitizer runs are retained under
`/Volumes/Fast SSD/CORTANA-Builds/parser-utf16-boundary-20261108/first-original`.
The original matrix exits 65: six of twelve cases fail. Both empty and
one-byte chunks consume two bytes; little-endian decoding combines an adjacent
fake trail beyond its declared two-byte chunk. Separate true two-byte heap
allocations cause AddressSanitizer two-byte read violations in *both* endian
decoders at `unicode.h:57` and `:67`. Each first outcome, full diagnostic and
binary remains available.

An independent original-valid-control failure also appeared: the existing
big-endian decoder does not combine a four-byte lead/trail pair whose trail is
`0xDD8B`. Its `U16_NEXT_BE` macro tests the raw second `uint16_t` value before
byte-swapping it. This failure is outside upstream 5549, so the precise
upstream boundary correction alone is not expected to make the complete matrix
green. Preserve the valid big-endian case and its original failure. Do not
silently choose a symmetric surrogate, remove the case, or attribute this
failure to the boundary correction. The next isolated-copy comparison must
report every same case and require the boundary failures to clear, while
identifying the retained big-endian pair failure as a separate open defect.
No combined runtime adoption is permitted on an unexplained red matrix; a
distinct pre-implementation decision and reproduction are needed before any
correction to that decoder's pair semantics.

### Big-endian surrogate conversion: separate pre-implementation slice

The original twelve-case console is that reproduction: a fully supplied,
valid big-endian `D83E DD8B` pair decodes as an isolated lead surrogate and
consumes only two bytes, while the same little-endian pair succeeds. The first
original outcome and the bounds-only candidate both retain that exact failing
case. The bounds-only candidate corrects five boundary rows, and its true
two-byte little- and big-endian heap probes exit zero without sanitizer
findings; its complete matrix still exits 65 with this one valid-pair failure.
The bounds-only outcome is evidence, not a passing decoder qualification.

The independently maintained upstream
[fix 5912](https://github.com/tree-sitter/tree-sitter/pull/5912), merged as
`351bd71e528659938243e324ef91cfa1515827ea`, changes only the trailing
surrogate reads in both `U16_NEXT_LE` and `U16_NEXT_BE`: apply the respective
`le16toh` or `be16toh` conversion *before* testing and composing that unit.
The exact pinned `unicode.h` lacks both conversions. Do not infer from this
source match that a normal editor journey hit the bug; the fixed input is a
C decoder/API control.

Before changing this candidate, preserve the complete bounds-only red result,
unchanged driver and source diff. Then copy the already isolated lookahead
candidate into a new named composite source tree; apply exactly the two bounds
edits from 5549 and the two trailing-surrogate conversions from 5912 to its
`unicode.h`. Do not rewrite the prior copies or change the C driver/fixtures.
For the composite, require all twelve ordered boundary/valid controls to pass,
both true two-byte heap probes to pass with AddressSanitizer and
UndefinedBehaviorSanitizer free of findings, the existing eight-case
lookahead matrix to retain zero mismatches, and the existing 324-pair C
subtree corpus to retain all equality/ownership checks. Verify the only runtime
source differences from pinned `3b1fb00f` are the selected `parser.c` lookahead
guard and these exact `unicode.h` corrections. Public C API and exported
symbols must remain identical. Stop on any changed result outside these
expected corrections, timeout, new warning or unexpected source delta.

The prior wrapper and normal app-path limitations remain. A passing composite
console permits a dependency-publication proposal; it does not qualify the
Swift package, app, native editing, user-visible performance or release.

The isolated composite now has that component result. Its complete evidence is
`/Volumes/Fast SSD/CORTANA-Builds/parser-utf16-boundary-20261108/composite-runtime/composite-qualification-proof.json`;
the original and bounds-only firsts are retained beside it. The original
twelve-case decoder matrix has six failed rows, the bounds-only candidate one,
and the composite zero. Both true two-byte heap cases and the twelve-case
matrix pass under AddressSanitizer and UndefinedBehaviorSanitizer with no
reported findings. The unchanged eight-case lookahead output and 324-pair
subtree output match their prior passing candidate bytes. The combined C
program has the same 268 exported symbols as the original. Among the exact 48
copied runtime source/header files, only `parser.c` and `unicode.h` differ;
the latter is byte-identical to the maintained upstream file at blob
`196c6bf416b6bf7c2e4efcd67a5ef083a90f49ab`.

This result does not change the publication boundary: the dependency fork,
Swift wrappers, manifest pins, compliance record, hosted resolution and app
qualification have not yet adopted the composite. Keep the already published
PR146 firsts independent and preserve its source while they are assessed.


## First console admission refusal

The first original-runtime driver exits 2 at its non-error parse admission,
before producing complete comparison JSON. Its source, actual binary, compiler
commands/diagnostics, libSystem-only linkage, partial stdout, full stderr and
bounded outcome are retained externally. The exact parse phase and tree were
not captured; this is not a reproduced application bug or semantic comparison.
Before changing any admission or fixture, add phase-labelled root/error facts
immediately before that same guard. Keep its refusal, source bytes, ranges,
encodings, lifetimes and all equality predicates unchanged. This diagnostic
revision must identify whether the assumption of error-free partial syntax is
valid; revise this architecture explicitly before any policy correction.


Phase diagnostics locate two actual original-runtime defects in the first UTF-8
case: expansion retains `(inline)` while an independent fresh parse contains a
code span; shrinking the previous valid full tree produces an ERROR node while
the original fresh narrow parse is error-free. The driver then exits 2 at that
incremental-error guard, so the other three cases have not yet executed. This is
component failing-before evidence, not an observed app failure or performance fix.

Retain both complete first console outcomes and exact driver binaries/sources.
For complete four-case reporting, collect incremental error trees as failed
semantic results instead of aborting at the first one. Fresh narrow and full
reference parses must remain error-free; final success still requires complete
ordered equality for every unchanged/expanded/shrunk tree, including error/missing
flags and positions. Thus no incremental ERROR can pass. Keep every original
fixture, range, encoding, lifetime and comparison predicate. This changes failure
collection only and must produce an honest nonzero original-runtime outcome.
Then compare the exact upstream guard on an isolated C-source copy; do not edit
or publish the owned runtime until all actual before/after controls are proved.
