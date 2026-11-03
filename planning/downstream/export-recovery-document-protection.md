# Protect open documents during export recovery

## Owner summary and baseline

A completed export scratch file may subsequently be opened as a document. Its
creation receipt must not authorize removing that open source. Extend the
existing document-publication protection to recovery candidates, preserving the
file and prior primary when a conflict is observed. Baseline: main
`190d02a0f3ebc04e8d2a9250d70dc946acb27c7c` (primary recovery and attribution inputs
integrated). This supplements the [primary recovery contract](export-primary-recovery.md)
and the existing destination/live-document architecture under MostlyText #11.

## Ownership and interfaces

ExportService retains protected physical file identities inside each
`ExportDestinationAdmission`, guarded by one private lock. Existing source/open
URL and retained-identity checks populate that set. Recovery registers its exact
owned candidate as an additional protected target; subsequent document
publication already passes through the same admission in
`ExportDocumentProtectionRegistry`. No global document lookup, actor dependency,
new permission or ambient storage is introduced.

`ExportRecoveryProtection` pairs that admission with its existing lifetime lease.
The lease gains an internal cleanup-ordering cutoff: it serializes the short
rename/unlink operation with document publication/revocation, without authorizing
primary publication or abandoning safe cleanup just because cancellation arrived.
The original active/cancellation checks for primary promotion remain unchanged.

## State, concurrency and failure policy

- Capture protected source/open-document identities before rendering, including
  unlinked sources represented by their retained physical identities.
- Register the authenticated scratch/quarantine candidate before inspection.
  Refuse recovery immediately if its identity is already protected.
- Recheck under the cleanup cutoff before rename and before unlink. Hashing,
  private checkpoints and directory synchronization stay outside that cutoff.
- If the object is adopted while quarantined, preserve it at its current
  quarantine path and report recovery required; do not move or remove the newly
  adopted source. A fresh later export can reconcile it after the document no
  longer protects it. Preserve the prior primary throughout.

The existing registry still allows the document publication and revokes the
export. Locks are not nested across registry revocation: admission checks release
their lock before the lease is revoked. Candidate checks inside the cleanup
cutoff use the same ordering as primary publication. Files adopted after a
completed destructive cutoff retain the existing document-publication
linearization and source-snapshot checks; this is not arbitrary filesystem
compare-and-swap or exclusion of hostile same-UID writers.

## Invariants, budgets and interoperability

A valid receipt remains necessary but is insufficient when the physical file is
protected by a document. Never infer removal authority from a path, public marker
or copied bytes. The per-admission identity sets are discarded with the export;
there is no global/persistent document cache. Existing byte/file/resource budgets,
HTML/assets formats, private record schema, dependencies, PDF behavior and native
acceptance guards remain unchanged. Reuse existing localized preservation/error
messages; no new native control is introduced.

## Files, slices, evidence and completion

Allowed: admission/protection/lease and primary-recovery helpers, writer call
sites, focused package/helper tests and architecture/status documentation.
Do not alter native account rules, renderer activation, test thresholds or pins.

1. Demonstrate the open-scratch regression on the baseline with a real owned
   fixture and the ordinary writer.
2. Implement retained identities and recovery-target checks through the existing
   registry; add initial URL/retained-ID/hard-link and late-adoption controls.
3. Run the source-bound non-application controls Debug/Release, strict lint/pinned
   format, compile-only locked Release and complete hosted checks before merge.

Stop if this requires changing document publication ownership or new native
behavior. This slice is done after those checks, reviewed merge and issue updates;
whole export/GUI acceptance, companion inventories and PDF gates remain open.
