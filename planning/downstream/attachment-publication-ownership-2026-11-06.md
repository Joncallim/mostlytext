# Keep asynchronous image resolution with its current displayed source

## Owner summary

An older image request must never replace newer Preview text, including when
the newer source contains no images. Inspect and test the actual pinned Textual
attachment model, then repair only demonstrated publication ownership defects.
This is a separate narrow unit under #13/#17. It does not establish the cause
of PR100's mounted-copy failures or replace its real consumer/viewport checks.

## Baseline and readiness

Start from main 4fda20fe5e7ba79b756a3b4bac97db284ebe0933, with Textual
c52cb5834c4695109aad2cb66294eafbc8f264c8 and all 24 current locked dependencies.
Current source keeps a resolved attributed string in a stable observable model.
An asynchronous call publishes after its task group without a request-version
or cancellation check; a later source without image/emoji URLs returns without
clearing the prior resolved value. Treat these as hypotheses until exact-model
controlled regressions fail on the original revision. PR101's separately
qualified registry observation hook does not change this interface; incorporate
its actual merge and requalify combined source if it lands first.

## Ownership and allowed changes

The Textual model owns publication of its derived attributed string. Its caller
continues to own source, directory authority, parser/frame identity and loader
lifetime. Change only the private model's request ownership/reset behavior in
the existing owner fork. No new public API, parser, loader, directory grant,
network access, renderer, product string, signing setting or dependency family.
Keep image and emoji resolution, all original output bounds and source bytes.

Expected implementation, only after baseline proof: assign a private immutable
request identity for attachment work at non-cancelled entry, clear obsolete
resolved content when new work starts, and reject cancelled/superseded completions
before publication. An image-free entry invalidates the previous identity with
nil and clears the old result without allocating an unnecessary request UUID.
A request already cancelled before entry must not clear a newer result. No
await may separate the final identity/cancellation check from publication.

## Controlled proof

Use the actual WithAttachments model and its actual attributed-string input.
Controlled attachment loaders suspend a real model request and then reject it;
no fake renderer or decoded image is presented as consumer proof. Cover:

1. A source without attachments replaces a prior resolved image source.
2. A cancelled older request cannot overwrite a newer source after resumption.
3. An older uncancelled completion cannot overwrite a later request's result.
4. A request cancelled before entry cannot clear/replace current content.

Require exact displayed-character bytes and a genuinely entered held callback,
with bounded event waits and guaranteed release/drain. Preserve the original
failure in both Debug and Release before accepting a candidate. Copy the same
canonical tests without adapting their bodies. Record all source, fixture,
manifest, executable and immutable pin receipts; reject partial/skipped runs.
Native module execution is hosted macOS 26 only. Local work is compilation and
pure orchestration checks; no owner app, native test helper or GUI launch.

## Integration and limits

If a repair is demonstrated, publish one immutable revision in the existing
owner fork, verify unchanged original MIT text, change only that dependency
pin, and reconcile inventory/notices/SBOM and patch provenance. Full app/package
CI, actual selected Debug/Release model tests, formatting, strict lint and a
separate source review are required before expected-head integration. No
upstream contact or external source-offer/publication is authorized here.

The unit cannot close the whole Preview issue. Production routing, native copy,
resource authority, viewport behavior, signed permission, final UI and exact
release artifact gates remain separate. If the hypothesis is disproved or a
fix requires public API/authority or broader rendering changes, stop this unit
and record the result rather than extending its scope silently.

## Original-model proof and final control precision

Hosted run 42208657007 at app source 837ddd1fc92b80c134ed01f84aaa591ddd9e1a56
completes all four controls with exactly the four intended failures in BOTH
Debug and Release. Independent source readback verifies 1,585 original input
hashes, 1,587 orchestration hashes, all 24 pins, the generated manifest, exact
fixture and unchanged original model/MIT bytes per configuration. The original
model is c52cb5834c4695109aad2cb66294eafbc8f264c8. These are model-publication
defects, not proof of PR100's native-copy cause. Full app CI for the deliberately
unrepaired original head was cancelled while both jobs were still queued; it
is neither a passing candidate check nor additional baseline execution.

Final controls distinguish an actual retained current resolved value from the
caller's source fallback. Only an image-free replacement may qualify through
the fallback. Cancellation/supersession controls require the current resolved
value itself to remain present and byte exact. Final hosted before/after runs
copy this same strengthened canonical file into both phases. Rehash the
orchestration source after execution and retain the generated manifest bytes
with the receipts.

## Shared app-test ownership prerequisite

Before final full-app qualification, include the independently reviewed two-line
ValidatedExportPanelTests ownership correction from d9c3cc70. Its standalone
Swift-owned NSWindow must disable automatic release on close before presenting
the real cancellation sheet, as required by the
[AppKit ARC contract](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed).
The immediately following app host crashed in PR101's original run; the stack
alone does not establish that fixture as its cause. Keeping the known ownership
violation in this branch would unnecessarily leave the same app-test hazard.
Carry only that test-file correction, not PR101's unrelated production hook.
Keep all real sheet assertions/deadlines and full final CI. This adds no product
window policy or historical crash-resolution claim.
