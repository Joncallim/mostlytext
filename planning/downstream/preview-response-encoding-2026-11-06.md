# Verify HTML Preview encodings in real WebKit

## Owner summary

HTML files using supported byte-order marks should display readable text, and
local resources should receive their actual file type and appropriate encoding
metadata. Verify the existing behavior in the real browser engine rather than
inferring it from fabricated response tasks. This is the remaining response
encoding criterion of MostlyText #13; final signed-app and owner acceptance
remain separate.

## Baseline and authority

Actual main is d607098bdb5046c02d81137b497e0ffe1aa01748. This test-only unit
starts at PR100 source bd84a68eac020c6c42112eeb27051e4c9209fa04 so it can use
the production connector once that independently qualifies. Incorporate its
actual merge and require fresh combined checks before integrating this unit.
Follow issue-121-handoff.md: the main document is decoded by FileCore and served
as UTF-8; UTF-8 HTML subresources receive meta hardening; non-UTF-8 resources
keep their bytes and authoritative response-header protection. Charset is sent
only when known. Unknown extensions receive application/octet-stream. Do not
invent automatic decoding, replacement bytes, broader grants or new MIME rules.

## Tests and boundaries

1. Write genuine UTF-16 little- and big-endian BOM HTML fixtures. Decode them
   through the actual FileStore, then show the resulting saved document using
   SecuredHTMLPreviewView.Coordinator and require the non-ASCII title in actual
   WebKit. Inspect UTF-8 immutable main data and unchanged original file bytes.
2. Load genuine BOM HTML subresources through the actual bounded scheme handler
   and directory-grant backing. Require the real WebKit title, the original
   delivered bytes and text/html without a fabricated UTF-8 charset. Authored
   scripts must not replace the title; response CSP remains present. This tests
   response handling directly and does not authorize a new production navigation.
3. Load a page containing an ordinary PNG positive control, UTF-16 SVG and XML
   fixtures, and an unknown-extension HTML payload. Inspect actual browser image
   completion/dimensions and the real delivered MIME/encoding/header/byte values.
   Require readable supported SVG and a non-image fallback for the HTML payload.

A test-owned forwarding WKURLSchemeHandler may observe real WebKit tasks and
delegate every start, stop, response, byte and terminal call to/from the unchanged
BoundedHTMLPreviewHandler. It supplies no synthetic response or resource loader.
Bounded fixture-only retained observations are disposed with the actual handler.
Host-injected JavaScript may read DOM values for assertions; authored JavaScript
stays disabled and CSP remains unchanged. Apple documents that
[allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript)
controls web-content JavaScript, independently of host inspection.

Use isolated temporary files, explicit directory-selection fixture receipts,
retained real backing and deterministic cleanup. No owner data, permissions,
external network, app signing, new public interfaces or production source edits.
Keep the existing five-second native readiness bounds and all existing test,
budget, mutation, positive-control and workflow limits. Native execution remains
hosted macOS26 only; local work is source tools and unsigned compile-only.

## Completion and stop conditions

Add the suite to the existing six-job consumer selection and exact receipt
counts; retain all old tests and all actual mutation/restoration pairs. Require
complete Debug/Release executions, immutable source/pin receipts, full normal CI,
strict tools and orthogonal source review. If actual browser behavior contradicts
the declared contract, preserve the failure and amend the architecture before a
production policy change. This unit cannot close whole issue #13, signing,
security-scope lifetime or final Release dogfood from MIME evidence alone.

## Combined qualification amendment — 7 November 2026

The owner-authorised E08 integration follows
[release-source-convergence-2026-11-07.md](release-source-convergence-2026-11-07.md).
The exact unit history remains an ancestor of the combined source. Incorporate
all reviewed units before publication of the integration candidate and require
all original positive, negative, mutation/restoration, source/pin and full CI
gates again on that single final source. This supersedes a requirement to merge
each intermediate source separately before assembling the next unit. Main
remains unchanged until the complete combined candidate qualifies. Original
failed/pending results retain their own SHA and outcome; no historical receipt
is retargeted or ceiling/deadline/selected assertion weakened. Owner-account
native execution and final release gates remain held.
