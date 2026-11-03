# Recovering a known primary export scratch file

## Owner summary

A process crash can leave a completed HTML staging file beside an export and
prevent the next export. The first durable recovery slice records that one
owned object privately, before promotion. On the next explicit export to the
same destination, MostlyText can retire the unchanged staging object safely.
Changed files, unknown residue and an unfamiliar primary are preserved and
reported. This adds no background directory scan or automatic document opening.

Companion-asset inventories, interrupted asset staging and obsolete-resource
collection remain subsequent work under MostlyText #11. This slice does not
claim the complete managed-directory crash policy. PDF printing and all native
acceptance requirements retain their existing prerequisites.

## Baseline and reconciliation

Baseline: main `ba7ff31b80ee55848c04c9c0d7b0e277d16eb5fe`.
`ExportFilePublication` already pins destination descriptors, stages through
exclusive no-follow files, checks the selected destination again at publication,
and uses memory-only `ExportOwnedFileReceipt` for quarantine retirement.
`ExportPublicationRetention` refuses unrecognized scratch residue. A public
primary-bound marker permits cautious companion reuse but grants no deletion
inventory. The new private record does not change that distinction.

This is the dependency-first primary-recovery slice of the binding
[export architecture](../epic-12-implementation.md) and
[managed-directory contract](issue-118-handoff.md). The latter's complete
asset manifest and pending-resource inventory are still required.

## Journeys and invariants

1. An explicitly selected HTML export stages and syncs its primary bytes, then
   syncs an authenticated receipt before attempting primary promotion.
2. A later export to that exact output finds a pending receipt. It hashes the
   current primary using a bounded streaming read. Only the recorded prior or
   desired primary state permits recovery; an unknown state disables removal.
3. Recovery retires only the recorded scratch inode with matching metadata and
   digest, or completes its recorded quarantine. Unknown objects are preserved.
4. If promotion succeeded, record-finalization failure is a nonfatal localized
   warning: the completed output is still returned. The next export reconciles
   the pending record.

No file is adopted because its bytes or name resemble an export. No public
marker or user-supplied JSON becomes a deletion receipt. No primary is deleted
or restored by recovery. The existing destination admission and document-alias
checks run again after recovery and before publication.

## Ownership, interfaces and storage

ExportService owns the journal, codec, recovery and filesystem operations. A
public Sendable `ExportRecoveryLocation` contains an explicitly injected private
storage URL; it has no owner-profile default. The app injects a child of the
post-migration `ApplicationStorageLocations.dataDirectory`. UI-test and existing
unit constructors retain explicit isolation and do not acquire ambient storage.
The package gains no new dependency: Foundation, Darwin and CryptoKit suffice.

The private directory must be local, ownership-enforcing, current-user-owned,
mode 0700, no-follow and without granting access-control-list entries. The key,
lock and record files are mode 0600 regular single-link files. A newly created
directory receives an exclusive 256-bit local authentication key. Existing
storage without a valid key is refused; it is never silently reprovisioned.
This key is unrelated to signing, notarization or updates and is created lazily
only when the real user performs an export. Tests use owned temporary fixtures.

One stable private lock serializes cooperating processes for the duration of
recovery and publication. It is acquired without waiting; contention fails
before writing output. A process-only directory gate remains in place.

The record name is SHA-256 of an unambiguous encoding of parent device, inode,
birth time and exact UTF-8 primary leaf. Records also include that binding.
A pending record contains operation ID, prior primary digest (or absence),
desired digest, primary scratch name/receipt, and a chosen quarantine name.
An idle record retains only the binding. Records are authenticated with
HMAC-SHA256 (a keyed message-authentication code) over a versioned bounded payload
before the payload is decoded. Receipt reconstruction requires the authenticated
loader's capability. The storage root's physical pathname is not signed, so
moving the whole trusted installation does not invalidate its key and records.

## State, concurrency and failure model

`idle -> staged receipt durable -> primary promoted -> idle`.
Recovery: `pending -> primary-state check -> quarantine durable -> rename without
replacement -> verify quarantined object -> unlink -> idle`.
The quarantine name is written before rename. A crash at either side of rename
can therefore be reconciled. A mismatch restores without replacement where
possible; an occupied original path preserves both objects and reports recovery.
A crash before a complete receipt is durable remains unknown residue and is
refused by existing retention checks. No inferred ownership fills this gap.

The synchronous writer performs no MainActor/UI work. Cancellation remains
checked before publication; recovery checkpoints/removal complete as a small
bounded critical section. No cancellation exception after successful primary
promotion may turn success into a false failure. Descriptor-relative operations
and post-read identity checks remain mandatory. Durable file and directory
sync failures fail closed before promotion, or warn after promotion.

The private store is trusted producer state against accidental corruption and
untrusted output-side content. It does not defend a compromised process running
as the same UID that can read the key or replace private state. Neither the new
journal nor existing quarantine checks claim a true compare-and-swap unlink
against arbitrary hostile same-UID writers.

## Budgets, interoperability, accessibility and localization

Each envelope is at most 64 KiB; each private directory has at most 1024 entries.
Primary hashing streams in 64 KiB chunks up to the unchanged final-HTML ceiling,
with one growth-probe byte. Only one pending primary exists per bound output.
The journal stores hashes and filesystem identities, never source/HTML text.
It transmits nothing. Exported HTML/assets and public markers retain their
existing formats. No new native control is introduced; failure and post-commit
warning prose uses the existing localized ExportService diagnostic flow.

## Verification matrix and adversarial corpus

Required controls: authenticated reopen; wrong key, corrupt/truncated/oversized
record, wrong binding/schema; owner/mode/ACL/symlink/hard-link/FIFO rejection;
lock contention; prior/desired/absent/unknown primary; same-byte different inode;
changed payload/permissions/metadata; crash on both sides of quarantine rename;
occupied restore; successful promotion with pending-finalization warning;
unknown residue; distinct leaves and aliases; repeated ordinary and self-contained
exports. Existing export publication/admission/retirement controls must stay green.

Local execution is limited to exact-source non-application fixture harnesses.
Run strict lint, the pinned formatter, hosted locked full package/app/CLI checks,
and compile-only locked Release. Native application, signing and clean-install
acceptance are separate and are not established by these checks.

## Files, slices and completion

Allowed: ExportService journal/publication/receipt helpers and tests, injected
app storage plumbing, AppSettings storage location and architecture/status docs.
Do not change PDF callbacks, resource budgets, native test guards, dependency
pins, migration copy policy, compliance predicates or held preview consumers.

1. Authenticated bounded private store and receipt reconstruction; corruption,
   ownership and contention tests. Stop if storage requires ambient user access.
2. Primary receipt/recovery state machine and streaming primary-state check;
   adversarial crash/identity tests. Stop if unknown content would be removed.
3. Writer/app injection, localized post-promotion warning, regression/full hosted
   checks and compile-only Release; update #11 with precise remaining asset work.

This slice is done only after all three units are integrated, reviewed and tested.
Whole-issue completion additionally requires the asset manifest/journal, printer
scratch policy, native PDF feasibility/parity/progress and acceptance matrix.
