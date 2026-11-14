# Near-page-limit PDF calibration

## Owner summary

Keep one large document-modal PDF export as a recurring Release regression just
below the existing 256-page limit. The earlier 200-section probe was too small
to characterize this boundary, and an aggregate sentence count concealed one
missing sentence balanced by a duplicate. The 430-section modal diagnostic
produced 252 paper pages with all 10,320 sentences, 24 within each section.
This change makes those per-section checks part of the guarded calibration.
It does not set the final memory or PDF byte budget or qualify a signed app.

## Architecture and evidence

The production app's ordinary window-backed journey uses document-modal AppKit
printing. [PR #278](https://github.com/Joncallim/mostlytext/pull/278) refuses
oversized vector fallback pages because the old slicer could duplicate searchable
text and could not recover glyphs clipped at WebKit's source-page boundary.
This branch carries that policy and changes only the private Release test and
its exact-source verifier. No new production hook or publication path is added.

The earlier [six-case diagnostic](https://github.com/Joncallim/mostlytext/actions/runs/43547645299)
showed the 430-section document-modal path succeeds at 252 pages, 547,594 PDF
bytes and 3.2218 seconds print/validation, with test-host peak RSS 418,250,752
bytes and sampled app peak 441,253,888 bytes. Independent PDF inspection found
all 430 headings in order and exactly 24 complete sentences under each heading.
The same run's 460-section non-modal artifact had 11,037/11,040 sentences with
several wrong per-section counts, despite an apparently plausible 236-page
result. A separate 460-section modal print produced 269 complete pages and
correctly refused the 256-page cap. These outcomes justify using 430 modal as
the positive near-boundary case and keeping oversized non-modal sources on the
fail-closed path.

## Qualification and limits

The hosted verifier requires five distinct passing cases: self-contained HTML,
short modal PDF, 200-section modal PDF, 430-section modal PDF, and source-cap
refusal. It binds the Release executable, committed inputs, selected tests,
run outcome, output digests, page geometry, exact phrase counts and memory
samples. The test checks every section separately, so one missing phrase cannot
be masked by a duplicate in another section. This is a fixture-specific sample;
the final export resource policy, broader visual corpus and exact signed RC
remain in issue #11.
