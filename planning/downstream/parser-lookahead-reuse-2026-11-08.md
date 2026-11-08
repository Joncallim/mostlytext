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

## Concrete local adoption preparation on main `a46c57c4`

The owner-maintained tree-sitter fork has a separate **local**, unpublished
branch `fix/lookahead-utf16-correctness` at
`1884982a418525e2e251ba331da929fccd354f3f`. It descends from the exact
active `3b1fb00f` and changes only `lib/src/parser.c` and `lib/src/unicode.h`
among product source files. Its new `lib/tests/utf16_decoder_boundaries.c` and
`MOSTLYTEXT_PATCHES.md` are outside the Swift product source list. The original
MIT and `Package.swift` bytes are unchanged. The fork is not yet a remotely
resolvable immutable dependency.

The current graph has three owner-maintained dependency revisions:
SwiftTreeSitter `76f93e7e325dcd05561a13ed63bcc92cb85be8da` pins C runtime
`3b1fb00f`; Neon `6074d1a50c7076b2e59d8d0619554b542e096afa` pins that
SwiftTreeSitter revision; MacDownKit and the vendored TreeSitterMarkdown
manifest also pin SwiftTreeSitter `76f93e7`. The MacDownKit manifest pins Neon
`6074d1a`. Its actual 24-row `Package.resolved` retains those and all other
reviewed owners. `MacDown2/project.yml` has no direct parser dependency pin.

That source chain is now prepared in separate **local**, unpublished children.
SwiftTreeSitter `7cf83c59f1d7b6fdbd6ae3b0e212c9824fbf103d` descends from
`76f93e7` and changes only its `Package.swift` revision from runtime `3b1fb00f`
to `1884982a`. Neon `7afa1dc49511a0d154f38810725d6984968ec2e6`
descends from `6074d1a` and changes only its `Package.swift` revision from
SwiftTreeSitter `76f93e7` to `7cf83c5`. Both manifests parse as Swift syntax;
no Swift runtime/test/grammar/query bytes change in either child. These exact
commit objects are not yet remotely resolvable. Only after PR146 is qualified
and merged into main may the application branch pin the two new child commits
in MacDownKit,
pin the wrapper child in TreeSitterMarkdown, and adopt an **actual hosted SwiftPM
resolution**. Do not synthesize `Package.resolved` or change any of the other
21 dependency revisions. The already qualified Textual revision and all
subsequent main changes must be inherited, not regressed.

The application-owned C qualifier previously accepted the older combined-source
and subtree changes relative to `5ce80b6f`. The local branch now extends it
narrowly: fetch that baseline, the exact `3b1fb00f` parent and the candidate;
require the
candidate-to-parent product diff to be exactly `lib/src/parser.c` plus
`lib/src/unicode.h`. Reconstruct both changed files by applying once the
literal reviewed upstream guards/conversions to the parent bytes and require
byte equality. Preserve the existing exact `Package.swift` transformation,
13 effective C inputs, unchanged public headers and MIT bytes, 324 ordered
subtree/ownership outcomes and bounded shared-work positive/negative controls.
Add the fixed application Markdown included-range probe and the fork's fixed
UTF-16 decoder probe to the same complete-source receipt; require original
semantic/bounds failures to be retained and candidate normal/sanitized controls
to pass. Inspect standalone linkage before execution and hash every actual
source, binary, raw output and pin. A changed file name or hunk is a refusal,
not permission to broaden the accepted runtime.

The pure qualifier's six local negative controls for wrong owner/revision,
duplicate pin, missing grammar, extra runtime file and mutated parser/Unicode
patch pass; its original-versus-candidate C matrix also records the original
failures and candidate normal/sanitized passes. The publication and app
integration slices remain separate: publish exact fork commits; inspect full
remote trees and licences;
run actual hosted lock resolution; update inventory/notices/SBOM; then perform
fresh package/app/Debug/Release/native edit, injection, geometry and issue-gate
qualification on one exact source. No release or whole-issue completion claim
follows from the local C results.

### First hosted dependency-resolution receipt

After the three exact fork commits are remotely visible, publish a separate
application branch whose first change is a guarded hosted **resolution probe**.
The probe runs only on an owner-repository push to that named branch, on a
macOS 26 runner with Xcode 26 selected. It checks the exact remote fork heads,
the unchanged original application manifests and the complete 24-row lock,
then copies the package tree to runner temporary storage. Only the temporary
MacDownKit and TreeSitterMarkdown manifests receive the new SwiftTreeSitter
revision; only temporary MacDownKit receives the new Neon revision. Run SwiftPM
resolve there with a finite deadline, retaining the full command, stdout,
stderr, exit and resulting lock. Accept the lock only if those three owner
revisions change to the exact published commits and every other pinned row,
location and version remains byte-for-byte the original lock's data. The
workflow uploads the first receipt and actual lock even if later validation
fails. It does not build or launch the app, write to main or alter PR146.

The first resolution runs against the current pre-PR146 branch and can establish
only that graph. If PR146 changes main before application adoption, inherit its
exact manifests/lock and repeat resolution on the new baseline. Commit app
manifest pins and the **actual** hosted lock only after a complete, passing
receipt for the same source. A synthesized lock, a green package parser or a
green pure-C probe cannot substitute for this hosted result. Keep #18/#19
native app acceptance and any performance claims open.

### Separate hosted C source qualification

Preserve the first successful hosted graph artifact from run `42487278217`
before another candidate run. A separate, owner-push-only workflow on the
isolated parser branch will use a macOS 26 ARM runner. It downloads that exact
artifact with read-only Actions permission, verifies its qualified receipt,
raw lock and staged manifests against fixed hashes and the unchanged source
manifests, and checks that each remote fork branch still points to its reviewed
commit. Verify the remote commit trees and original license blobs before
running C code. These are source facts, not a claim that a fork's own CI ran.

Create a disposable checkout in runner temporary storage; copy only the
artifact's two staged manifests and actual resolved lock into it. The tracked
application checkout and PR146 remain untouched. Run the existing pure-C
qualifier from that disposable checkout so its exact source inventory includes
the temporary graph. It must retain the original runtime's expected red
Markdown/UTF-16 controls, the candidate's normal and sanitizer controls,
all 324 ordered subtree/ownership cases, linkage, work bounds, all source and
binary hashes, and complete first stdout/stderr/status. Upload the evidence
even on failure. Do not call this a Swift package build, native editor test,
whole-document latency result or whole-issue closure.

### Sanitized hosted probe timeout diagnostic

The first hosted C-source run, `42488511441`, passed the graph, pin-refusal,
normal 324-pair comparison and shared-work controls. Its exact candidate
AddressSanitizer/UndefinedBehaviorSanitizer executable then exceeded the
60-second process deadline. The first runner log, artifact, binary, source
hashes and blank stdout/stderr are retained under
`/Volumes/Fast SSD/CORTANA-Builds/parser-hosted-c-source-20261108/first-run`.
The empty output does not locate the stall because stdout was redirected to a
regular file and may remain buffered until process exit. The runner wrote no
status file on `TimeoutExpired`. The same fixture, runtime source, JSON grammar
and compiler flags completed an earlier isolated local sanitized probe in
0.528 seconds; that result cannot replace the hosted red run.

The next hosted run is a diagnostic of this exact failure. Preserve the first
artifact and execute the same unmodified candidate fixture and sanitizer
binary under the same 60-second total bound. If it remains active after 15
seconds, take a two-second process stack sample, with a five-second sampler
limit, without extending the probe deadline. Always write the process result,
elapsed time and timeout status, and upload the sample or sampler error. A
sampler failure is diagnostic loss, never permission to accept a timed-out
probe. Keep all existing comparison, original-red, Markdown and UTF-16
predicates, hashes and pin checks. Name the new artifact separately. A green
second run is a second data point; it does not erase the first timeout or
establish native app acceptance.

The diagnostic run `42515117999` also timed out at 60 seconds. Its retained
sample caught the main thread before `main`: the old Xcode 26.0.1 AddressSanitizer
runtime entered `AsanInitFromRtl` again through macOS allocator initialization,
then spent all 173 samples waiting on its own static spin mutex. The C fixture,
parser and comparison functions were not reached. The diagnostic artifact and
full log are preserved under
`/Volumes/Fast SSD/CORTANA-Builds/parser-hosted-c-source-20261109/diagnostic-run-42515117999`.
The workflow selected Xcode with the first alphabetical `Xcode*.app` path,
which was 26.0.1 and Apple clang 17. The local passing proof recorded its
`clang` command but not the selected Xcode version; the current local compiler
reports Apple clang 21. GitHub's [macOS 26 ARM image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
lists Xcode 26.6 as its default and also retains 26.0.1. Select and assert
Xcode 26.6 explicitly in the next hosted C-source run. Keep the exact fixture,
sanitizer flags, 60-second deadline, source/pin checks and all failure
predicates. This is a compiler runtime isolation test, not proof that older
sanitizer versions are generally
broken or that the parser candidate is qualified. Preserve the second red
artifact and give the new result a separate artifact name.


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

### Hosted Swift package qualification before pin adoption

The next owner-visible result is whether the two wrapper forks and the staged
MacDownKit package pass their **complete** macOS package suites with the exact
candidate parser graph. Current `main` is `d605d92ed6adc196bf0e679461dd8896443f6847`;
the staged app graph is deliberately the earlier, immutable run `42487278217`
from checkout `e9a294d84f0cfb54bc8610a92461aa848fcacfec`. This diagnostic does
not rebase that receipt onto current main, change a production pin or launch the
app. A passing staged test is therefore necessary evidence for the candidate,
not an adoption or current-main integration result.

Use a manual-only job on the existing `ci.yml` workflow, which is already on
the default branch and can be dispatched against the isolated parser branch.
A new branch-only `workflow_dispatch` file would not receive GitHub's manual
event. A manual CI run on `epic/05-parser-hosted-graph` skips the regular CI jobs;
all other CI refs retain their existing jobs. The diagnostic has read-only
repository and Actions permissions, selects macOS 26 ARM and Xcode 26.6
explicitly, and writes only to runner temporary storage. It downloads run
`42487278217` by fixed run and artifact name, then validates every original
artifact byte hash and its success receipt before testing.

For each fork, require the published branch to point to the reviewed commit,
fetch that exact commit, check its tree, licence and manifest blobs, parent and
single-file manifest diff. Require SwiftTreeSitter `7cf83c59` to change only
the C revision to `1884982a`, and Neon `7afa1dc4` to change only the wrapper
revision to `7cf83c59`. Checkout and initialize their test grammar submodules
in disposable directories. Resolve each package, retain the actual resulting
lock, and require the parser pin rows to equal the hosted app graph. Neon's
unrelated Rearrange row must remain the fork's tracked pin. Run each unfiltered
package suite with `--force-resolved-versions` and serial tests.

Stage the artifact's two app manifests and actual 24-row lock into a disposable
MostlyText checkout. Resolve again and require the lock bytes to remain exact.
Build MacDownKit and its tests under that lock; run both XCTest and the full
Swift Testing suite using CI's owned helper procedure. Preserve full per-command
logs, exits, first failure lines, source and submodule identities, test-host
hashes, resolved locks, and a receipt on success or failure. The staged suite
does not establish app-target, Release, native editor or signing acceptance.
After a complete pass, separately reconcile current main, compliance inventory,
and full app/CLI/Debug/Release/native checks before any production pin adoption
or issue closure.

The first manual package run, `42517950815`, passed the Xcode 26.6 host,
frozen graph artifact and exact remote source checks but stopped before any
package command. Its SwiftTreeSitter submodule update checked out the committed
`tree-sitter-swift` gitlink `eda05af7`, then the local verifier rejected it:
the general Git-output helper stripped the leading space that `git submodule
status` uses to mark a correct checkout. The failed receipt, full job log and
source facts are preserved at
`/Volumes/Fast SSD/CORTANA-Builds/parser-hosted-packages-20261109/run-42517950815`.
The narrow correction reads that status output without stripping its first
column and requires the exact path and committed gitlink for each fork. It
still refuses uninitialized, changed, conflicting and unexpected submodules.
This failed attempt provides no Swift package test result.
