# Localise editor-owned cmark failure details

## Owner summary

Three cmark bridge failures can reach the export alert as English-only details
inside its already-localised summary. Put those details in the existing export
catalog. Keep their diagnostic descriptions, error identities and rendering
behavior unchanged. This source correction supports MostlyText #3 and #11;
final language review and native export acceptance remain separate.

## Current source and ownership

Start from main `8158068771a2012c27885d7ac4808cf73af7ffb1` plus PR52's qualified
candidate `51bcbfa3a7756b662c7414ab83d99614e794a5f7`. Incorporate its actual merge
before final combined checks. `CMarkGFM.CMarkError` is an editor-owned enum, not
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
localized details reaching `ExportError.renderFailed`, and all four compiled
catalog resources. Locally execute only the unchanged Foundation value enum
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
