# Read actual character placement before correcting PDF text verification

## Owner outcome and live baseline

Main19481c0edc424215ea55d1afc8d9df6709b65b37 integrates the exact original-PDF
readback. Native42427273752 atsource5d2ab0f7 proves its original canary guard fails
because PDFKit emits separate NATIVE/EXPORT/CANARY and underscore lines, while the
actual visual heading is contiguous. Merely removing whitespace would produce
NATIVEEXPORTCANARY__ and could accept a visually wrong NATIVE EXPORT CANARY__.
The real extra blank page is separate product evidence, not an oracle excuse.
The complete actual first results, source/predicates/PNGs and integration proof
are committed byte-exact before this increment; old records remain untouched.

This bounded read-only increment obtains the actual public PDFKit per-character
geometry for the same immutable16424byte canary. It supplies enough evidence to
construct a placement-aware fixed-fixture oracle later. No source fixture, old
validator, product pagination or acceptance threshold changes here; zero app/GUI
launches. Product/dependencies/pins/current private caller authority unchanged.

## Ownership and interfaces

Only ReadActualPDF.swift gains per-page character_count/raw_utf16_count plus
character_geometry entries: each rawUTF16index/text and public characterBounds.
Require PDFPage.numberOfCharacters equal the raw NSString length and at most
16384 before indexing; reject nonfinite geometry, preserve zero/empty geometry
for separators (CGRect.null is explicitly recorded as null/no rectangle, never
converted to invented coordinates) and never invent visible glyphs. Read characterBounds(at:) from
this actual PDFPage, not pypdf coordinates or inferred source placement. Exact
PDFSHA/size, original guard counterexample, actual raster/page/text proof and
all existing host/root/source limits remain. No shell, authored script, renderer,
network or filesystem authority is introduced.

## Failure, performance, interoperability and evidence

No async worker or shared state; all reads occur in the already bounded standalone
hosted native process. At most10pages*16384constant-size records, this fixedcanary
has fewer than200characters. Text remains bounded16KiB/page and actual rasters
612x792. A count/geometry/API mismatch is a failed first diagnostic, not a new
fallback or normalisation. Preserve it before any correction. Native character
indices/text are raw evidence, not complete PDF text extraction semantics, general
RTL/reordering support, visual fidelity, whole-export or final signed acceptance.

## Slices and stop conditions

1. Commit this decision and13exact completed first records frommain19481c0e.
2. Add only bounded public character readback; strict Swift6SDK typecheck only,
   format/strictlint, existing pure admission controls/source/old-validator/PNG
   implementation preservation, YAML/compliance locally. Native/PDFKit execution
   remains on guardedGHA, not the held owner account.
3. Freeze and obtain complete first native/Compliance outcomes, retaining all
   original data/logZIP/artifacts. Independently verify exact source/bytes and
   actual glyph rectangles/text against both PNGs; then define a separate exact
   placement oracle and production pagination decision before their code.
4. Scoped orthogonal self-review, honest issue11/8/17 update and expectedhead merge
   if this read-only increment is ready. No original broad acceptance row checked.
   Stop on count/API differences or a need for extra authority/source behaviour;
   revise the contract before changing either. Do not retry unchanged failures.

## Revised decision: preserve actual index mismatch before further code

Current main38f14a37eb8aa80033f54eb8ba468ecb2630135c additionally merges stable
native process receipts; product/PDF inputs remain unchanged. The complete first
native42430812014 and Compliance42430811950 at402d7752 both pass. Their actual
checkouta21cd891 uses main19481c0e; all five canonical source hashes and original
16 records, failed original predicate and both raster hashes are independently
verified. The ten exact records in pdf-character-index-first-2026-11-08 preserve
these complete firsts and their logs before this correction.

Actual page1 has81 raw UTF16 units and81 native character indices; page2 haszero.
Despite equal counts, index6 is a raw newline with a nonempty glyph rectangle;
index18 is raw R with height about2, while initial heading capital rectangles
have height about13. The last six raw indices have empty rectangles. Equal counts
therefore do not establish text/geometry correspondence. The earlier text label
and proposed future glyph interpretation must not be used as an oracle.

Revise only the private readback: rename text to raw_index_text, retaining its
actual raw NSString substring. Record the actual public page.attributedString
string and its UTF16 count separately; enforce the same16KiB text bound without
assuming equality or alignment. For every existing native index, obtain public
page.selection(for:NSRange(index,1)), its optional string (bounded256UTF8bytes),
and its actual selection bounds for that page. Preserve missing/null/empty
states explicitly and refuse other nonfinite bounds. Index reads remain bounded
by native numberOfCharacters and the existing equal-count guard for this exact
fixture, not general PDF extraction semantics. No reconstructed or invented
glyph text, whitespace stripping, position tolerance or acceptance predicate.

No product, original guard/PDF, raster implementation, host authority, packages,
workflow or caller changes. Strict SDK typecheck only locally; actual PDFKit
observations run on guarded hosted macOS. Obtain and retain complete firsts for
the revised source; independently verify source and actual observations. Stop
before any semantic canary oracle until the APIs demonstrate their relationship.
This remains read-only diagnosis, not corrected pagination/export acceptance.
