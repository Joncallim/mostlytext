# Verify the ordinary PDF canary by actual character placement

## Owner summary and ready baseline

The ordinary export acceptance check must recognize its fixed visible heading,
`NATIVE_EXPORT_CANARY`, without accepting misplaced or reordered characters.
PDFKit returns this fixture's words and underscores in separate raw-text runs.
A bounded, read-only acceptance helper will verify the actual PDFSelection for
each non-whitespace UTF-16 character and reconstruct only the heading's single
visible row. This changes test infrastructure, not export output or product policy.

Baseline main is `7867621005a65950bb0db994b8cddaa2f5367412`.
AGENTS.md, EPIC_STANDARD.md, RELEASE_HARDENING.md, live issue #11 and the existing
readback/canvas source and retained actual selection JSON have been inspected.
PR155 has already corrected the unused-canvas blank page with qualified native
PDF output. PR147 remains frozen and failed; its original validator and PDF must
remain unchanged. This helper does not complete that ordinary-menu journey.
The renderer activation prerequisite remains separately blocked by PR146.

## Fixed inputs, ownership and interfaces

A new read-only Swift helper under `.github/hosted-export-acceptance/` reads only
two exact admitted packet PDFs in the disposable hosted root. It imports PDFKit,
Foundation, CryptoKit and Darwin, never the product or WebKit. It reports bounded
page text and actual single-character PDFSelection strings and rectangles. It
requires each page's UTF-16 count to equal PDFKit's character count; missing or
mismatched non-whitespace selections refuse. Raw `characterBounds(at:)` is not
used: the prior native observation proved that its index mapping cannot be
assumed to match raw text for this fixture.

A pure Python helper owns packet admission and fixed-fixture placement policy.
It loads gzip records only with safe leaf names, regular nonsymlink files, bounded
compressed/decompressed sizes and exact known hashes. Original PDF SHA256 is
`ce2b5cc91a8a774c894c43d0f1fe56d4f95cce32171a80c8c2b0f70785af0ae6` (16,424 bytes).
Corrected canvas PDF SHA256 is
`d95a9e149c236e572551cc6cc913bc044d80822c8a14796a438ce6f5171aab08` (15,107 bytes).
Both are immutable historical outputs, not newly generated or exact-RC exports.

## Placement policy and failure behavior

For this one fixed short fixture, the heading consists of the uniquely largest
selection-height row: exactly 20 ASCII characters, with a height strictly larger
than every non-heading character. Every selection must match its raw character,
be finite, positive, inside the media box and have a unique UTF-16 index. The
heading's y and height agree within 0.01 PDF point, accommodating floating-point
serialization only. Sort that row by actual x, require strictly increasing x and
centers, and adjacent box edges within 10 percent of the row height (font advance
rectangles can slightly overlap). Require the exact ordered canary, with no
missing, extra or duplicated character. Do not strip and concatenate raw text.

The original two-page PDF must report a correctly placed heading but still
refuse the fixed short-fixture acceptance because it has two pages. The corrected
one-page PDF must satisfy both placement and page-count predicates. This is not
a general PDF semantic parser, font validator, arbitrary export sanitizer or
blank-page deletion policy. Authored multi-page documents use different tests.
No error is converted into success; original failures remain preserved.

## Trust, execution and resource limits

Local work is Python source/data controls and Swift syntax/SDK typechecking only.
Actual PDFKit/font execution occurs only on the existing guarded macOS 26 ARM
GitHub runner, runner uid 501, with both owner profiles and Fast SSD absent.
No app/GUI/WebKit launch, signing, credentials, dependency resolution or network
content occurs. Read at most 4 MiB per packet record, 10 pages and 16,384 UTF-16
units per page; subprocess runtime is bounded to 30 seconds and job to 8 minutes.
Capture full stdout/stderr to files, source hashes and downloaded actual compiled
helper bytes. Preserve complete first workflow logs/artifacts before correction.
No additional concurrency, cancellation, accessibility, localization or public
API behavior is introduced. No user-facing strings or dependencies change.

## Slices, evidence and stop conditions

1. Commit this architecture before implementation. Add pure placement and packet
   admission controls using the exact previously observed selection JSON, plus
   reordered, missing, duplicated, off-row, off-page, nonfinite, invalid-index,
   wrong-selection, extra-page and collapsed-position hostile variants.
2. Add the guarded native two-PDF read-only comparison. Independently verify
   source, input hashes, actual helper bytes, all raw outcomes and the complete
   first. Stop if actual selection representation differs; preserve it and revise
   this architecture explicitly before changing predicates.
3. Review the bounded infrastructure change, run Compliance and the native
   comparison, merge only on complete proof, and update issue #11 with scoped
   results. Existing original unchecked criteria stay open.

A future ordinary-menu activation must consume a reviewed helper contract and
run its own new actual export, Cancel and normal Quit. This retained-output
comparison is necessary evidence for that oracle, not a substitute for it.

## Qualified integration

[PR157](https://github.com/Joncallim/mostlytext/pull/157) is integrated as main
`23de8c25b61598b87fb807e5a3dfd74c81e2e4d4`. Both complete first workflows pass:
[native 42447473633](https://github.com/Joncallim/mostlytext/actions/runs/42447473633)
and [Compliance 42447473478](https://github.com/Joncallim/mostlytext/actions/runs/42447473478).
Source `1eb8d941`, actual tested `4b17469c`, computed integration and actual merge
share tree `679ef068afcd30d0c1695c99dc2abfc2f53168cc`, with expected main/source
parents and a clean canonical checkout. Product and compliance trees are unchanged.

[The exact first packet](evidence/placed-pdf-canary-qualified-firsts-2026-11-08/README.md)
retains all actual inputs, selections, complete first logs and integration proof.
Independent readback verifies eight source bindings and the downloaded actual
helper bytes. Both first-page non-whitespace selection records exactly equal the
prior original native observation; no guessed glyph-bound mapping is used. The
original has two pages and refuses, the corrected fixture has one page and
accepts. Both visibly ordered headings are exact. Native stderr is empty and
fully retained. Fourteen hostile controls, 332 Compliance tests, strict SDK
typechecking, formatting and lint pass. GitGuardian passes. All five original
unchecked issue #11 criteria remain open, as do ordinary-menu/normal Quit,
complete-operation progress/cancellation, full visual/parity, final calibration
and exact signed-artifact acceptance. Review is scoped orthogonal self-review.
