# Durable stdin admission before command acknowledgement

## Owner summary

A valid command stream becomes a dirty untitled Markdown document, including
empty input. Preserve exact UTF-8 source, BOM, line endings and final newline.
Before exposing a window or acknowledging it, secure its managed recovery epoch
and a verified canonical session record that refers to that same document/epoch.
No temporary saved filename, source normalization or buffer-only success claim.

Baseline: integration d73fcf7a, stacked #559/#560. The receiver already validates
bytes off MainActor, reserves bounded input capacity through admission and owns
logical close receipts. File and activation opens exist; stdin is currently
refused. This unit replaces that refusal, without activating legacy migration or
changing the whole-application bootstrap/consent surface.

## Transaction and session ownership

Serialize stdin admissions through one coordinator-owned keyed lane. Decode via
FileByteDecoder with explicit UTF-8 and the protocol byte limit off MainActor.
Create a managed FileDocument, mark it dirty even when empty and verify recovery.
Then construct an ordinary window model/controller, but keep it in a separate
private staging pool: it is not a visible/current document or a Close All target.

All ordinary canonical session snapshots and their current-generation comparison
include staged controllers. Invalidate older captured session snapshots when a
stage is registered or withdrawn; never allow an older autosave to erase the
restoration reference. Use the existing recovery-first, conditional/read-back
verified canonical publisher. The stage's document ID, epoch, exact text,
mutation and encoding remain fixed until publication is proven.

After a successful verified publication, recheck admission/termination and stage
ownership. Bind its stable logical lifetime, move it into the ordinary controller
pool and show it synchronously, without suspension across binding/exposure. The
receipt may then acknowledge. Additional file paths use the existing open path;
if stdin cannot be admitted, reject before opening any associated files.

Quit suspends receipt admission before its recovery/session snapshot. A staged
source is included if it was already registered; an input still preparing may
not create a new stage after suspension. A cancelled Quit resumes normal work;
a confirmed safe Quit never permits another binding. Successful Save As uses
the existing durable source/destination transition and keeps the logical CLI
lifetime. Cancelled close remains pending; confirmed retirement completes wait.

## Failure and recovery limits

Before recovery/session verification, no visible document or acceptance is
reported. On failure, withdraw and dispose only the hidden controller, invalidate
its obsolete snapshots and report recoveryUnavailable. Never delete or roll back
recorded recovery or a verified canonical record: another session publication
may already have preserved it. A failed/unacknowledged request may therefore
leave retained recovery, and a concurrently committed session can restore it.
Success guarantees a restoration reference; failure does not promise that an
unacknowledged input is discoverable or that no recovery record exists.

A crash after canonical publication but before showing/acknowledging retains the
same dirty document for normal session restoration. No new recovery format,
filesystem journal or parallel canonical writer is introduced. Unknown/future
session state still refuses publication under #558. Aggregate input limits stay
reserved until actual admission completion, including disconnect and the queue.

## Verification

Foundation-only factory controls cover empty/BOM/double-BOM/mixed-line-ending
input, strict invalid encoding, oversized input and failed recovery; all use
private temporary recovery roots. Hosted app controls require a real canonical
store and prove hidden-before-publication, ID/epoch/encoding restoration,
Save As byte fidelity/lifetime, refusal without UI on publication failure,
and older-autosave ownership. Run strict lint/format, Compliance, locked full
hosted package/app suites and Debug/Release builds before merge. Native public
pipe/Save As/close-cancel/Quit and exact signed-candidate acceptance remain open.

The first canonical-reader control caught an existing empty-recovery defect:
an untitled empty snapshot was restored as clean because updatingText treated
it as a no-op. Restore any recovered untitled snapshot as dirty, including
empty text. This prevents ordinary unsaved-only startup from dropping an
accepted empty/BOM-only stdin document. Retain the failing control.
