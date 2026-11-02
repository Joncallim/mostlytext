# Export input authority

## Owner outcome and baseline

Local images come from an explicitly retained directory capability, never from
reopening the saved document's parent URL. A missing or changed capability keeps
ordinary HTML's unresolved-image warning and fails self-contained HTML/PDF.
Safe in-root aliases remain supported; outside links and nonregular objects do
not supply bytes. This is the next bounded #118/#117 unit under their existing
handoffs. Integration baseline: 43f69717f0d04c4b603b4e7edfc42480be2c6d14;
master remains 15c0fae22f7618e94c82681227057c66011be2a9.

## Interfaces and ownership

ExportService adds ExportResourceAccess, an immutable Sendable owner of the
existing LocalResourceAccess.DirectoryLease. ExportRequest separately carries
this capability; documentURL supplies metadata only. Capability equality is
object identity, not a pathname equivalence claim. Opening a capability uses
only existing process access: no chooser, scope expansion or Preview grant.
The ordinary app snapshot opens it after panel acceptance and retains it across
all renderer awaits. Untitled/unavailable directories have no capability.

ExportResourceResolver uses ResourceReference and ContainedResourceReader for
all image bytes. No Data(contentsOf:), file-size pathname probe or second
canonical-path approval remains. The shared reader reports its resolved leaf
name so an image-looking alias cannot package a non-image target. Keep MIME,
distinct count, per-file and aggregate limits. Reads stay serial on the existing
composition worker. One candidate is capped at the per-file limit before it
enters memory; only distinct admitted identities commit aggregate/count quota.
This preserves alias deduplication at the limit, with at most one bounded
uncommitted candidate and no concurrent reservation oversubscription. Hash the
exact immutable snapshot that will be packaged.

## Cancellation and failure

Each preparation owns a ResourceCancellation bridged with the Swift task's
cancellation handler. It reaches the large-stack cmark thread and the reader's
64-KiB checkpoints. A cancelled read throws CancellationError, never an image
warning. Root replacement/closure, invalid references, FIFO and enforcement
failure follow unresolved policy without pathname fallback. Actual read bytes
and MIME determine the manifest. No renderer receives a mutable descriptor.

## Tests, slices and limits

1. Capability/request/resolver and shared resolved-name regression, with real
   private filesystem fixtures and the existing syscall-barrier controls.
2. Ordinary snapshot and explicit test-fixture grants; compile-only app checks
   locally, full package/app execution and locked Debug/Release builds hosted.
3. Strict formatting/lint, Compliance, source-hash-bound Debug/Release harness,
   failing-before controls, review, exact-tree integration-only merge and issue
   readback. Keep every first failure.

Fixtures cover no grant despite a saved URL, renamed/replaced root, outside and
safe in-root symlinks, misleading extensions, Unicode/percent paths, FIFO,
oversize/count/aggregate limits, cancellation, deduplication and real composer
policy. Existing LocalResourceAccess syscall-interleaving tests remain required.
No local app/app-target execution: EXECUTION_HOLD stays unconditional.

This unit does not enable #519/#520 or the optional SVG path, change the PDF
print bridge, invent source access from an open-file grant, or claim final
sandbox/native acceptance. Authorization-time output/source-alias admission,
inventory journals and automatic crash repair remain separate source units.
Empirical Release limits, platform probes, final independent review, signing
and public promotion retain their gates. No new third-party dependency or pin.
