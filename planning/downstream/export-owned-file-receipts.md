# Verify owned export scratch with streaming receipts

## Owner outcome and baseline

Export cleanup must preserve an object changed after it was staged, and it must
not allocate a second complete artifact just to verify temporary-file removal.
Capture a receipt of the known staging bytes and observed object, quarantine
without replacement, then stream-verify that object before deletion. Baseline is
b4a8f6a2 (#574); master stays 15c0fae2. This is a bounded #118/#183 building block
for recovery, not completed durable journals or native printer ownership.

## Source reconciliation and binding change

ExportPublicationFilesystem.retireTemporary currently reads another full Data
and compares only device/inode/type after quarantine. The expected Stamp lacks
birth time and ownership/permission fields, and retirement does not compare the
captured modification time. A same-object metadata change can therefore be
silently deleted; inode reuse is not additionally discriminated by birth time.

Extend the existing internal Stamp with birth, owner/group, permissions, link count and flags.
An internal ExportOwnedFileReceipt binds known staged bytes to the captured
regular-file stamp and SHA-256. It is memory-only, has no external decoder and
is not minted by reading an arbitrary file. A future journal must supply its
own trusted producer/storage authority; a JSON file or xattr beside the output
cannot by itself grant deletion authority. No key generation or owner-store
activation belongs to this slice.

Validate a single safe component before mutation. Require the complete captured stamp before quarantine, including change time.
After a known staging-body link operation, refresh that receipt from the owned
still-open descriptor. Keep the existing scoped quarantine prefix and no-replace rename/restore discipline. After quarantine,
open nonblocking/no-follow, reject an unexpected object/size/modified time/mode/
owner/group/birth before reading, and hash bounded 64-KiB chunks with at most
one growth probe byte. Recheck the opened and named stamp after reading. Compare known bytes/hash and stable metadata; after quarantine ignore only the
expected change time because our rename legitimately changes it. Unexpected current change
time during the read still rejects. Never unlink mismatched bytes or metadata;
restore without replacing, or report the retained recovery path if occupied.

Keep the old retireTemporary signature as the adapter for existing writers.
Cleanup retains the established non-cancellable bounded verification behavior;
this inspector is cleanup-only and does not replace normal cancellable resource reads. Do not infer strong arbitrary
same-UID writer exclusion from a final pre-unlink check.

## Discriminating proof and limits

Private real-file controls cover unchanged/empty/boundary content; changed
bytes, modified time and permissions; a byte-identical replacement inode;
post-open mutation/replacement; FIFO/symlink; traversal refusal; restore conflict
and preserved quarantine prefix. The prior retirement function must fail the
changed-metadata preservation assertions. Preserve existing publication/race
controls and run Debug/Release, strict lint/pinned format, Compliance, unsigned
compile-only app/UI targets and complete exact-head hosted checks.

No local app/app-target execution, owner preferences, system Trash, Daybreak,
test account, signing or master/public promotion. Durable private-ledger
integration, asset inventory/partial crash repair, printer scratch ownership,
Release calibration and final native/independent acceptance remain separate.

## Executed source evidence — 3 November 2026

The combined private harness passes 279 tests/31 suites in Debug and three
complete serial Release runs at the final source. Its 163 manifest-listed
production/test files match source, with only established app/CLI test module
imports adapted. The earlier unused validated-SVG DTO stub and theme fixture
helper remain excluded; no app, owner store or system Trash executes. Pinned
cmark/Markdown/Yams identities are unchanged. Twelve new receipt tests include
parameterized chunk boundaries and permission/time changes, plus extended
metadata changed after quarantine.

Restoring the old retirement function fails six actual assertions across the
permission/time cases: changed objects are deleted. Bypassing the post-quarantine
stamp check fails the xattr/payload preservation assertions. Both negative runs
are retained and the exact source is restored afterwards. Existing replacement
and restore-conflict assertions remain: the latter now injects replacement
after quarantine because the new early stamp check correctly refuses a
preexisting replacement before the hook can run.

The first Debug run exposed that restore-conflict fixture timing. A later
helper-signature compilation failure came from a private type alias; the public
internal signature now names the internal Stamp directly. Harness refresh path
mistakes stopped before test execution and remain in the work log. Two Release
runs overlapped full Xcode compilation and failed the unchanged JSON 100-KiB
50-ms gate at 66.069 and 51.244 ms. Preserve those failures; the first three
complete serial runs pass (that test takes 16 ms), and three further complete
serial runs at the final source pass after Xcode finishes. No timing ceiling,
assertion or known-issue marker changes. These controls do not establish final
whole-export memory/performance calibration.

Strict lint, SwiftFormat 0.63.1, 99 Compliance controls and inventory pass.
Unsigned build-for-testing compiles the real app/UI-test targets without
execution. Its fresh build exposed an earlier Trash fixture's mutable-local
capture warning missed by incremental compilation: an explicit MainActor
reference now models origin closure with every original assertion retained.
Final compilation has no new warning text against the retained baseline.
The source-only orthogonal review remains self-review. Complete exact-head
hosted checks and actual merge-tree verification are still required before
integration; no broader issue is closed by this building block.

External evidence: closure-review-20261102 on the Fast SSD, including
receipt-debug-idle-head.log, receipt-release-idle-head-{1,2,3}.log,
receipt-old-retirement-negative.log,
receipt-post-quarantine-metadata-negative.log, receipt-app-compile-final.log,
receipt-warning-comparison.json, receipt-lint-head.log,
receipt-format-head.log, receipt-compliance.log and receipt-harness manifests.
