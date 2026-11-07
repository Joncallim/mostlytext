# Prove Quick Look reply payload lifetime before production integration

## Owner summary and current baseline

Finder can keep a generated preview after the provider callback finishes. The
application must continue accounting for those bytes, and repeated data-factory
calls must return the same already-prepared content. Actual main is
d7cff043750123aea66e50406884ca73917885af. PR118 already proves a genuine cold
Finder static HTML/cid reply with exact minimal provider permissions. It does
not prove retained replies, repeated factories, system cancellation, failure-once
or slow real-renderer fallback. The production extension remains absent.

This narrow next platform-probe slice tests actual QLPreviewReply objects and
the identical factory closures passed to them on a disposable hosted Mac. It
adds no production target, shared renderer, app setting, dependency or file grant.
Original cold-Finder provider, UI method, permissions and workflow stay unchanged.
Owner desktop execution remains held; local work is source/type checking only.

## SDK reconciliation, ownership and data flow

The installed macOS26 SDK exposes QLFilePreviewRequest.fileURL and the
providePreview(for:completionHandler:) protocol method. There is no cancellation
method in either inspected header. The async import alone does not establish
framework cancellation propagation. Do not invent a callback or claim that
manually cancelling a task constitutes an actual Finder cancellation. That
separate named platform observation and slow real-renderer fallback remain open.

A private guarded console below .github/quicklook-retained-reply-probe creates
real QLPreviewReply objects with immutable HTML bytes and captures only a minimal
payload holder in their data factories. Each holder owns a process-local byte/
slot reservation; deinitialization returns that exact reservation once. The
factory uses its reply parameter and never captures its own reply, request,
provider or renderer. Keep a weak holder observation to distinguish retention
from callback completion. Framework-internal copies and decoded images are
outside this owned-payload accounting; do not infer total RSS bounds.

The probe may retain the exact factory closure to invoke it repeatedly on the
same real reply. These are explicit direct calls to the same block, not invented
repeated system requests. A real native QLPreviewReply owns that same block, and
its retained lifetime must independently keep the holder/reservation charged
when external factory/holder references are dropped. PR118's actual framework
factory call remains separate evidence.

## Invariants, adversarial cases and limits

Reserve before allocating payload data. Allow at most eight owned holders and
64 MiB of their actual immutable bytes. Prepare deterministic 1 MiB payloads;
fill eight holders, require ninth admission to fail without allocating, retain
replies after local preparation scopes finish, repeatedly obtain byte-identical
content, then drop replies in deliberately different orders. Exact count/bytes
must remain charged until each captured holder really deinitializes, then return
to zero. Separate overflow, negative/zero reservation and double-release controls
must reject invalid accounting without mutation. No file read, GUI, network,
signing key, product build or default-handler registration belongs to this unit.

Represent one request's result as an immutable terminal choice. Completion,
failure and cancellation must finish at most once; a late result cannot change
an existing reply or refund a retained holder. Test competing terminal choices
and cancellation of a distinct request while existing replies remain usable.
These are controlled request-state tests, not actual system cancellation proof.

A deliberate counterexample releases the payload reservation immediately after
reply construction while the real reply and its factory still retain the
payload. The identical native probe must fail at the first live-reservation
assertion; exact restored source must pass. No skip, ceiling increase, expected
failure or forced process termination counts as a pass. All three first results
and compiled inputs must be retained; no unchanged failed native retry.

## Execution, verification and slices

1. Commit this architecture before code. Inspect the actual SDK and preserve
   existing cold-Finder fixture bytes unchanged.
2. Add the small self-checking private Swift console and a hosted-only Python
   supervisor/workflow. Refuse optimized Python and any non-real runner account,
   home, UID, OS/architecture, temp root, checkout or repository before writes.
   Capture exact source/generated controls/compiler command/binary digests and
   owned lifecycle status. Type-check only locally; pure admission/result parser
   controls may run locally. No local framework-linked executable runs.
3. On genuine hosted macOS26 ARM, compile and execute original, counterexample
   and exact restored copies under bounded owned supervision. The counterexample
   must fail only its intended named retention condition, never compilation,
   launch, timeout, crash or another assertion. Bind actual compiled binary bytes
   to each execution and preserve them for independent readback.
4. Review exact source and immutable receipts, run ordinary compliance/security,
   merge only the reviewed/tested/computed/actual tree and reconcile issue7/17
   narrowly. A new private probe does not complete all QL-REPLY prerequisites or
   authorize the production extension/shared rendering.

No full-product/native Release latency, real rendering/fallback deadline, actual
Finder cancellation, framework-internal memory ceiling, final signed artifact,
owner/VoiceOver or whole issue closure is implied. If framework retention differs
from the proposed ownership, preserve the first refusal and revise this contract
before changing the model; never normalize the observation into a pass.

## Source preparation checkpoint

Strict installed-SDK type checking, pinned0.63.1 formatting, strict lint, eleven
pure outcome/optimized-admission controls, three owned-process controls, actual
CORTANA normal-host refusal, Python/YAML syntax and source compliance pass. Initial
formatting/one catch-placement refusal was corrected before any native publication.
No local framework executable was built or run. Original cold-Finder fixture,
controller, permissions/workflow and all MacDown2 bytes remain unchanged.

An unrelated FileCore regression PR136 may integrate while this independent
private probe qualifies. Before merge, intake its actual main and requalify the
combined head; source-only addition of unrelated tests does not erase any first
outcome. Preserve old and new exact checkout/product-tree identities separately.
Do not claim the first older full tree equals a later combined tree.

## First optimizing-compiler refusal and material correction

First source8421eb79/run42395882950 fails before native execution: -O with
warnings-as-errors diagnoses the permanently false earlyRefund branch as
unreachable. Strict type checking did not execute that optimizer diagnostic.
Native original/mutant/restored remain NOT_RUN. Both first workflow outcomes
(nativefailure, Compliancepass) and exact copied source/command are retained and
independently verified before this correction; no first result is relabelled.

Remove the disabled counterexample branch entirely from original Swift. The
private controller must instead insert reservation.release() at the unique
reviewed location immediately after real reply setup in its counterexample COPY
only. This keeps original source executable without suppressed warnings, while
the counterexample still physically refunds a holder retained by the same real
QLPreviewReply. The named assertion and expected42 outcome remain unchanged.
All three native phases, -O/strict concurrency/warnings-as-errors, actual bytes,
limits, terminal choices and lifetime assertions stay. No app/production policy
or architecture changes; first corrected native execution is mandatory.

## Actual qualified main intake

PR136 has merged at8b02cd6140c2c888eac700d201ea65f059dff426. Its actual parents,
treebb4b1ba3 and canonical fast-forward are verified. Intake that actual main and
preserve its complete qualified external-file executor packet alongside the
existing first native Quick Look packet. All six Quick Look execution input
blobs remain equal to qualified7581079d; the new root product tree includes the
separate FileCore test. A fresh first native/Compliance qualification on this
combined exact head is required before review/merge. Earlier758receipts remain
at actual6c52874c and tree6dbfbc33, never retargeted to this intake.
