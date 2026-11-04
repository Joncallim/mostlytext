# Localise editor-owned cmark failure details

## Owner summary

Three cmark bridge failures can reach the export alert as English-only details
inside its already-localised summary. Put those details in the existing export
catalog. Keep their diagnostic descriptions, error identities and rendering
behavior unchanged. This source correction supports MostlyText #3 and #11;
final language review and native export acceptance remain separate.

## Current source and ownership

Start from main `8158068771a2012c27885d7ac4808cf73af7ffb1` plus PR52's pending
candidate `51bcbfa3a7756b662c7414ab83d99614e794a5f7`. Incorporate its actual merge
before merge; combined checks may run first because this candidate already
contains PR52's exact source tree. Verify that the anticipated merge tree equals
the checked candidate rather than restarting unchanged runtime checks. `CMarkGFM.CMarkError` is an editor-owned enum, not
an opaque message returned by an external engine. `ExportComposer.renderBody`
wraps these errors in `ExportError.renderFailed`; the wrapper reads the
underlying `localizedDescription`. Its current `errorDescription` simply
returns the diagnostic `description`, bypassing the package catalog.

## Contract and limits

Only `CMarkError.errorDescription` changes: switch over the existing three cases
and use literal `String(localized:bundle: .module)` lookups. Keep `description`
as its existing English technical representation. Add the exact three keys to
the existing ExportService catalog with English source values and explicit
English `needs_review` drafts for French, Japanese and Polish. Do not invent
accepted translations or translate arbitrary system/renderer/source messages.
No public API, C bridge, parser, cancellation, resource authority, budget,
dependency, printing or native execution change is needed. If this requires
any such change, stop this unit and reconcile the architecture first.

## Verification and completion

Add package tests for every error case, unchanged diagnostic descriptions,
localized details reaching `ExportError.renderFailed`. Verify all four compiled
catalog resources by readback in the isolated Foundation fixture and actual app. Locally execute only the unchanged Foundation value enum
and export error values in an owned non-application fixture; do not run the
product, AppKit/WebKit or app-target tests. Use separate synthetic resource
markers and the actual old enum to show that removing the catalog lookup fails
real assertions. Production catalogs stay unchanged during controls.

Compile-extract the three literal keys, validate catalog/configuration coverage
and regenerate the canonical inventory. Run strict lint, pinned formatting,
full combined hosted package/app checks, locked compile-only Release and actual
resource/artifact readback. Record exact source, substitutions and failures.
Merge only after those checks pass; update the owning issues without claiming
final string freeze, translation quality, native UI or whole-issue closure.

## Source qualification checkpoint

Four Foundation tests in two suites pass in Debug and Release, using the exact
error enum, unchanged export error/diagnostic values, the production test file
and actual Apple-compiled resources for all four locales. Only the enclosing
cmark namespace is supplied in the isolated fixture; no C parser or app code
runs. Separate marker resources prove both the real LocalizedError lookup and
the existing export wrapper: the actual old enum produces six assertion failures,
the current enum passes, and exact restoration passes. A harness check initially
mistook Swift Testing's XCTest zero-test preamble for absent assertions; the
actual six Swift Testing failures are retained and the check was corrected.
Apple compile-only extraction confirms all three keys. Strict lint, pinned
formatting, source Compliance and 19 catalog/configuration controls pass.
The canonical inventory has 346 entries across the same 15 catalogs. Full
combined hosted checks, Release build and final artifact readback remain
necessary. PR52 must merge first and its actual main tree must combine without
changing the checked candidate tree before this unit is integrated.
