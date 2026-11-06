# Verify generated heading targets before resource publication

## Owner summary

A requested table of contents must reach the actual source headings without
corrupting packaged image references or overwriting an earlier export on failure.
This implementation unit adds the opt-in composition path and its structural
proof. It does not register production linked TOCs or native navigation yet.
The next unit must activate Preview and Export together after these boundaries
and SVG occurrence isolation have executed proof.

## Baseline and scope

Main is c07dd6629519cca7d7ce135f571d978ebe749e7e. The branch starts from
24e3fa9d6f95b52a9fdbe9f5807ea1a75cbc921f (PR96), including PR95's exact-ID
correction. Their interfaces are stable; qualification/merge remains a dependency.
Read EPIC_STANDARD.md, RELEASE_HARDENING.md, issue-117-handoff.md and
toc-production-activation.md. This document binds this narrow publication unit;
it does not silently authorize an incomplete production activation.

## State and ownership

ExportRequest adds an optional source-owned HeadingAnchorIndex (default nil).
ExportService retains the one fresh parsed MarkdownDocument alongside existing
metadata. It checks source generation, parse options/revision, source fingerprint,
heading inventory and accepted-splice coordinates against that index. The app
must still validate its document/recovery/window lifetime when registering and
executing navigation. An index alone grants no app action or file-read authority.

The no-index composition path retains its existing behavior and limits. The
opt-in path composes, renders with private heading markers and unresolved resource
tokens, settles the existing leaked-sentinel retry with a fresh resolver, registry
and source map, then verifies/patches headings. Only then does the final registry
resolve image URLs and mint body-bound resource slots. Never search resolved
URLs to reconstruct authority or relax slot hashes/ranges.

## Structural fast path

Raw-free cmark Markdown cannot emit authored IDs. Each actually accepted custom
fragment must independently satisfy HeadingFragmentStructure before this fact can
be reused. The streaming UTF-8 grammar permits balanced lists/list items,
paragraphs, links, emphasis/strong/code/deletion and void images/breaks. It enforces
parent content models, prohibits nested anchors, and forbids all generated anchors
in inline fragments because their authored surrounding context might be a link.
Unknown tags/attributes, identifiers/names, rawtext/foreign elements, comments,
unquoted/malformed attributes, controls and incomplete structures fail the proof.
Quoted values are scanned without copying long data URIs. Depth is bounded at64;
small names are bounded at16 bytes; each finite tag has a finite attribute set.

This is target-structure evidence, not sanitization, URL authorization or a trusted
flag. Rejection selects existing bounded emitted-DOM analysis without rewriting
authored markup. Accepted pure Markdown/fragments avoid imposing the8MiB DOM
ceiling on ordinary32MiB-source/128MiB-body export. Empty heading inventories
create no target authority. The existing template is fixed and introduces no IDs;
full-template regressions must guard that assumption before production activation.

Heading patching advances once through the body, instead of shifting the remaining
tail for every inserted attribute. Every original byte outside the proven spans
is preserved. Cancellation is checked around synchronous phases and before URL
resolution. The existing source/derived/body limits still apply. No work or DOM
object escapes as an unchecked Sendable value; no source/resource is fetched.

## Failure, accessibility and localisation

Unmatched source, ambiguous or conflicting generated targets and failed structural/
DOM checks throw the specific headingNavigationUnavailable error before any
primary or companion write. Preserve previous files. Add actionable strings to
the existing package catalog; French/Japanese/Polish entries remain explicitly
needs-review English drafts until the existing final language gate.
Preview production registration is deferred to its paired activation unit; there
it must isolate a failed TOC and preserve the authored marker with diagnostics.
No owner GUI, VoiceOver, browser/PDF, signing or separate-account acceptance is
inferred from this unit. Owner-account EXECUTION_HOLD remains.

## Discriminating tests and completion

Run the exact Foundation-only structural tests in Debug and Release locally.
Compile all actual package tests locally without execution. Execute actual-product
hosted tests for front matter, A/A/A-1 and Unicode links, images before/after
headings with URL-special output names, >8MiB pure Markdown, unchanged no-index
raw HTML, exact canonical authored IDs, opaque contribution conflicts, stale
source/generation, leaked-sentinel retry and previous primary/companion retention.
Compare accepted fragments against the actual pinned SwiftSoup parser to prove a
following heading remains a unique direct body child. Run full locked CI, format,
strict lint, compliance and hosted native regressions before merge. Preserve every
first-run failure. Neither #10 row can be checked from this prerequisite alone.

Stop and reassess on a false cmark/template structural assumption, source loss,
wrong targets, new dependencies, unbounded work, a need to weaken existing tests,
or an ordinary no-index export policy change. Remaining production work includes
SVG namespace policy shared with Preview, bounded heading worker/lifetime routing,
real native link/scroll actions and their hosted app-shell proof.
