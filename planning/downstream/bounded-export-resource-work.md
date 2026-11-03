# Bound repeated export resource work

## Owner outcome and baseline

An export containing many spellings or aliases of the same image must not read
and hash that image without a total work bound. Preserve explicit directory
capabilities, constrained no-follow reads, exact Unicode filenames, output
resource deduplication and destination-specific unresolved-resource policy.
Baseline is parse-reuse head ffb5f2b0; master remains 15c0fae2. This is a bounded
#118 source unit; it does not enable held features or native execution.

## Source-confirmed gap and approach

The resolver caches only raw URL strings. Query/fragment/percent/dot variants
can read identical files again, and distinct symlink/hard-link aliases can
bypass the distinct-content payload quota. A 65,536-slot input can therefore
perform far more I/O and hashing than its small final manifest suggests.

Cache the first result by the parsed root-relative path's exact UTF-8 bytes.
Do not normalize Unicode or infer equivalent symlink targets. Query/fragment
variants share an immutable accepted resource (or first refusal) for one export.
Keep every admitted authored reference registered for slot and manifest lookup.
Raw-reference and diagnostic keys also use exact bytes. ExportManifest adds a
sorted byte-exact referenceMappings audit list; its existing referenceMap stays
a compatibility view because Swift String dictionary keys merge NFC/NFD. This
prevents raw-reference lookup from undoing the path cache's Unicode policy.

Add an optional thread-safe ResourceReadAccounting to LocalResourceAccess's
existing contained directory reader. It counts attempts before path resolution
and actual positive read results before bytes are appended, including later
failed/mutated/non-image reads. The reader limits each syscall to remaining
allowance plus at most one byte for EOF/growth detection. At most one over-limit
probe per admitted in-flight attempt is possible; no subsequent attempt starts
after exhaustion. Existing callers omit accounting and preserve their policy.

Export supplies one meter for the entire composition: provisional 4,096 file
attempts and 256 MiB actual read bytes. These are work ceilings, distinct from
unchanged 512 distinct packaged resources/128 MiB payload and 32 MiB per file.
They allow duplicate payload work without admitting unlimited aliases. Tests
inject small accounting values through the internal resolver initializer; the
public API cannot supply a larger export budget. Exhaustion uses the existing
ordinary warning versus self-contained/PDF fatal diagnostic policy. A new
English catalog reason belongs to final E16; empirical calibration stays open.

## Proof and limits

Use actual private files and reader syscalls. Query/percent variants must reuse
the first frozen bytes even after the original name disappears; NFC/NFD remain
distinct. Hard links with equal content must consume read work despite one
packaged identity. Missing/non-image/oversized and post-read-changed candidates
must not evade attempt/byte accounting. Exact byte/attempt limits, EOF probe,
cancellation and the existing containment/race corpus remain required. Disable
path caching and accounting separately to show actual regression failures.

Run source-identical Foundation/POSIX controls Debug/Release, strict lint,
pinned format, Compliance, unsigned compile-only app/UI targets and complete
exact-head hosted CI. Retain first failures. No app/local app-target execution,
Daybreak/account/signing or public release. Journals, late-open alias protection,
printer scratch, native acceptance and final calibration remain separate units.
