# Execute the existing real PDF pagination controls on hosted macOS 26

## Owner summary

Verify that the existing long-document PDF export actually produces multiple
readable pages, and replaces a stale destination with a valid PDF. Execute the
real app adapter on hosted macOS 26 under a bounded owned-process runner. This
avoids launching any app or native helper in the owner's held account. The
historical local hangs remain failures and are not classified by this probe.

## Baseline and readiness

Live clean main is d607098bdb5046c02d81137b497e0ffe1aa01748. The root AGENTS,
EPIC_STANDARD, RELEASE_HARDENING, epic-12 implementation and #117/#121 contracts
were inspected, together with current #11/#8 and actual PDFExportAdapter/tests.
The actual adapter uses a locked WebKit page, NSPrintOperation, bounded output
validation, its existing vector fallback and exact destination publication.
The original two genuine PDF tests are permanently disabled because earlier
local xcodebuild runs could not obtain required OS services, one hanging3328s.
That does not prove current hosted macOS26 cannot execute them. Existing native
app controls now use hosted macOS26 and exact-owned bounded execution.

## Scope and unchanged contracts

Only make the two existing tests available under a dedicated test compilation
condition PDF_PAGINATION_PROBE; otherwise they remain disabled as before. Keep
both complete bodies and original multipage/text/atomic-replacement assertions
byte-identical. Do not change shipping PDF code, parser, CSP, budgets, progress,
print cancellation, dependencies, default CI behavior or any native policy.
No new user-facing strings, public API, accessibility or persistence change.
The normal product export, including its existing printable-output fallback,
is the behavior under test; successful PDF output does not establish which
internal printer path produced all marks or prove native Cancel responsiveness.

## Ownership, execution and failure behavior

A separate pull-request workflow compiles the actual Release app and all test
bundles with testability, the existing RELEASE_PREVIEW_PROBE support condition and
PDF_PAGINATION_PROBE. The first compile confirmed the ordinary native folder
fixtures require the existing support condition in Release; retain that compile
failure. The PDF opt-in boolean is nonisolated because it reads only a build
condition and the Testing trait evaluates in a Sendable closure. Serialize this one suite because AppKit print operations are process-owned;
async MainActor tests alone can interleave while awaiting WebKit. Execute all9
existing tests in PDFExportAdapterTests, not a copied adapter, mocked printer or replacement
harness. Keep the repository's owned-app executor unchanged:600s complete-run
bound;120/240s exact-app samples; identity/path/UID/process-birth guards; normal
exit evidence; owned cleanup only. A40-minute job bound includes clean compile
and artifact collection. Never execute this workflow locally in the held owner
account. A first hang or assertion failure is retained with logs/receipts and
is a stop condition for unchanged execution, not a reason to raise limits,
remove positives, skip a selected function or retry until green.

Record every tracked app/package/project input, verifier/workflow/owned-executor
hash, synthetic checkout and exact24 canonical pins before compilation; require
those inputs unchanged afterward. Require Release configuration, the explicit
condition, owned normal exit without timeout/cancellation, every selected test
name and exactly9 functions/1suite passed with no skipped/issue markers. Retain
full logs, identity/status/samples and exact locks even on failure. Independently
verify artifact hashes against the Git objects before any acceptance statement.
Test receipt validation with lightweight Python controls, including truncated
selection, omitted positives, skipped tests, failure and missing/timeout status.

## Slices and completion

1. Commit this architecture before code. Add the opt-in condition to the two
   disabled traits while preserving their function bodies. Add the dedicated
   hosted workflow and strict exact-input/result verifier plus its pure tests.
2. Run pure verifier/ownership/compliance controls, strict format/lint, inventory
   and unsigned actual Release build-for-testing; no local native execution.
3. Publish through the E08 combined qualification PR referencing #11/#8, under
   release-source-convergence-2026-11-07.md; run the single hosted Release attempt
   and full normal CI. Independently review exact source/pins/execution. Preserve
   the first outcome. If failed, inspect the actual cause before any material
   repair and fresh qualification. Only merge on complete exact-head gates and
   final review/tree equivalence.
4. On success, update only the narrowly worded real-PDF-pagination row and
   strongest-evidence ledger with exact source and limits. Whole #11/#8 remain
   open for export menu/RC, memory budgets, progress/cancellation and other debt.
   This does not qualify signed permissions, separate-account clean install,
   VoiceOver, owner-observed export or the exact final RC.
