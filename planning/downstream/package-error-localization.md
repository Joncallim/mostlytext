# Localise decoding and unavailable-workspace messages at their owning packages

Open/Save displays FileCore's FileDecodingDiagnostic.message directly. Quick Open
and folder search expose WorkspaceFileIndex.State.failed(String). These messages
are currently English literals. FileEncodingMetadata also asks Bundle.main for
its BOM suffix, but the package ships no catalogue. Give FileCore and TextSearch
their own processed String Catalogs and route these existing messages there.

Baseline: #47 combined head 75f80853147bdaf3fe7452c4f8d7e2c359703ae8; main
is d86a15c8 while that branch qualifies. Related contracts #3 and #6. Commit this
reconciliation before implementation and retain the pending notice-only tranche
when integrating. No native fixture or app/profile execution is needed.

Preserve every English string, byte offset, encoding detection/losslessness rule,
actor generation, failed-root snapshot invalidation and failure reason. The
encoding names UTF-8/UTF-16/etc remain technical data; only the existing prose/BOM
suffix is translated. Do not turn source encoding into a presentation decision.
Register four FileCore keys and two TextSearch failure keys with explicitly
needs_review French/Japanese/Polish drafts. The manifest adds processed Resources
only to those two existing targets; no new dependency or public API is introduced.

Remove FileCore's obsolete exception from the existing package-localisation
source guard; every String(localized:) call now uses its owning package bundle.
Use existing encoding/index regressions, the strengthened guard, compiled catalog
inspection, complete hosted package/app CI, strict lint/pinned formatting,
Compliance and locked compile-only Release. Verify actual app resource bundles
and the embedded/public CLI resource path contract. Do not add tests that merely
repeat wrappers. Final language/layout/VoiceOver and the whole-project string
freeze remain separate; no broad #3/#6 or native acceptance is claimed here.

## Translation-resource reconciliation

The same source audit found ten .tx/config entries for thirteen pre-existing
catalogs: Math, EditorCore and CommandLineSupport were absent even before this
unit. Add those plus FileCore/TextSearch so all fifteen catalogs have exactly one
XCSTRINGS resource with matching source/filter paths and source language. Keep
existing organization/project slugs as the explicitly unconfigured placeholders;
no Transifex account/project, submission or external translation is created here.
Add a read-only static coverage validator and meaningful missing/duplicate/path/
type/language controls, enforce them in Compliance, and refresh the committed
localisation inventory. This is pipeline completeness, not translation quality or
final native string-freeze acceptance.
