# Route remaining export warnings through String Catalogs

Users should receive export warnings and resource/budget failure details through
the existing localisation pipeline. The source audit after #47 found direct
English strings in derived-fragment rejection, resource resolution, metadata and
raw-HTML policy warnings. The alert wrapper alone cannot translate these details.
This is a copy-routing correction; all source-preservation, resource admission,
safety limits, renderer isolation, cancellation and publication behavior remains.

Baseline: #47 head bd8be495fa245f8a8bcf8bd8a47e13f516c3215d, based on main
242054cf. Stack this independent unit on that qualified source; retain the #46
metadata correction when integrating. Related contracts: #3, #9, #11.

Commit this reconciliation before implementation. Wrap every user-facing direct
English diagnostic/reason in ExportService with String(localized:, bundle:
.module). Keep all existing English wording and original message/return sites,
including unknown renderer/upstream explanations. Technical URL paths, generated
HTML/CSS, MIME types and sentinel/filename construction remain literal data.

For dynamic range/debug values use an opaque String substitution with exactly the
same displayed value. Integer count and generation fields retain their types and
catalog placeholders. Supply all new keys in the package catalog; French/Japanese/
Polish additions remain explicitly needs_review. Register the existing NSOpenPanel
Open Folder prompt and route it, plus both Export panel prompts, through the app
catalog. No parser, bundle ownership or public interfaces change.

Use existing real ExportService behavior/adversarial tests and full hosted app/
package CI rather than adding tests that repeat string wrappers. Run catalog
structural/placeholder checks and their negative controls, Apple catalog compile,
strict lint/pinned formatting, Compliance and locked compile-only Release. Inspect
all touched strings against the actual dynamic interpolation types. Do not claim
final native translation/layout, all-project hard-coded string clearance, Preview
math semantics or any broad issue closure. Preserve the owner-account native hold.
