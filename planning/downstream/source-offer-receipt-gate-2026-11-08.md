# Bind public source-offer claims to reviewable evidence

## Owner summary

MostlyText's release check currently refuses the D2 and Graphviz source offers
because their public locations are still planned. When those offers are later
published, changing `status` to `verified` by itself would make this part of the
check pass. Require a small, committed retrieval receipt and an exact list of
expected public bytes before accepting that status. This protects the release
record from an accidental status-only edit. It does not publish source, fetch a
website, approve any component's rights or make the current release ready.

## Baseline and scope

Baseline is clean `main` at `a46c57c4b62376b67492cf67421a4961fdf55c1c`.
`compliance/tools/compliance.py` checks `source_offer.location` and, only in
release mode, whether `status == "verified"`. It deliberately never accesses
the network. `inventory.json` has two required offers, D2 and Viz.js, both
`planned`; its six strict release findings must remain six. Existing local
source-review archives and technical reproduction do not satisfy independent
rights review or anonymous public retrieval. Issue #14 LC-02/03/07/09 and
`compliance/ARCHIVE_PLAN.md` own those later decisions.

## Reviewer journey and data flow

After separately authorized source-only publication, a reviewer performs a
credential-free HTTPS fetch of each versioned source page and package from an
outside network. They record exact URLs, response status, byte counts and
SHA-256 values in a JSON receipt under `compliance/evidence/source-offers/`.
The inventory lists the expected URL/size/digest for every material and pins
the receipt's repository path and digest. `compliance.py check` then verifies
that the committed receipt is safe to read, byte-identical to its pin, and
agrees exactly with the inventory, including a successful fetch of the URL
printed in notices. This is a read-only offline consistency check. The actual
network fetch, its environment, the package contents, public availability at
release time, and legal approval require separate review and evidence.

## Contract and invariants

- A required offer with `status: planned` retains the existing release failure;
  no new field or receipt is required until it is asserted `verified`.
- A verified offer needs `materials`, a nonempty list of unique HTTPS URLs with
  expected lowercase SHA-256 and byte size. One material must equal the
  `location` embedded in the notices.
- Its `verification` points to a regular JSON file within
  `compliance/evidence/source-offers/` and supplies its exact SHA-256. Absolute,
  traversal, symlink and oversized receipt paths fail before reading.
- The receipt has schema 1, method `anonymous-https-get`, a UTC retrieval time,
  the same location and exactly the expected materials. Each material records
  HTTP 200, exact byte count and digest. Unknown fields are refused so a
  committed receipt cannot accidentally carry cookies or authorization data.
- Missing, stale, malformed, non-HTTPS, 404, empty, duplicate or mismatched
  evidence fails both ordinary and strict checks when status is verified.
  A reviewer still must inspect how the receipt was obtained; the checker
  cannot establish that a claimed network fetch actually occurred.
- No current component status, generated notice/SBOM, app resource, dependency,
  source URL or release-script behavior changes in this unit.

## Ownership, failure and security

The Python compliance tool owns validation. It reads only the repository's
dedicated receipt directory and at most 256 KiB per receipt. There is no
network access, subprocess, concurrency, user-facing app string, persisted
state, document input or new build dependency. A rejected receipt reports the
component and reason. The release cannot silently treat rejected evidence as
verified. The source-only publication and anonymous downloader remain later
LC-09 work; this change cannot authorize them.

## Test and execution slices

1. Commit this current-main architecture before implementation.
2. Add the narrow validator at the existing source-offer check. Update the
   synthetic passing compliance fixture with a synthetic bound receipt.
3. Prove a status-only edit, unsafe/unreachable URL, missing/stale receipt,
   failed HTTP status and mismatched material all fail. Run focused and full
   pure Python compliance controls, ordinary check, and confirm strict check
   still reports the same six open findings. Check notices/SBOM unchanged.
4. Host the exact branch in normal Compliance CI before a merge. No signed
   artifact or current source offer can be claimed complete from this unit.

Stop and revisit this contract if a real source offer requires a different
material shape, a credentialed URL, runtime network access in `compliance.py`,
or a status change in the current inventory.
