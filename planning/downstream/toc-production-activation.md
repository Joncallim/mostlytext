# Shared table-of-contents navigation

## Owner summary

A table-of-contents link should reach the same intended heading in native Preview
and exported HTML, without changing authored text or opening an unrelated file.
The first implementation unit prepares the source-owned heading index and bounded
work needed for that outcome. Actual production link activation remains a later
unit. Ordinary authored HTML policy and no-TOC rendering must remain intact.

Main is cb71b9cec71e9041ab6adbe808e1b72354ba0b92 after the qualified PR93 math
merge. The working branch starts from PR95d44c710d, including PR94's compiler
correction. Those stable interfaces are known; their own hosted qualification and
merge remain prerequisites. Read issue-117-handoff.md, EPIC_STANDARD.md and
RELEASE_HARDENING.md with this document. The first-unit contract below is binding;
later activation design remains a draft until its discriminating proofs pass.
Owner-account native execution remains held; actual native tests execute hosted.

## Source-confirmed missing behavior

TOCContribution.run produces a plain list. linkedMarkdownList exists but is internal
and unused. HeadingAnchorIndex/allocator, emitted marker/DOM matching, source splice
maps and optional SVG namespace are staged, not ordinary production callers.
PreviewLinkResolver ignores bare/current-file fragments. Raw HTML markup must keep
ordinary Export's existing policy. Never activate the separate strict/no-script
exportValidatedSVG route as a shortcut. No new module dependency is necessary.

## Critical resource-slot ordering constraint

Current ExportComposer.render renders cmark, then resolves its private generated
resource URL tokens and records ExportResourceSlots for the exact resolved body
and byte ranges. Adding heading IDs AFTER that step invalidates both the body
hash and every following slot range. Heading patching must happen BEFORE the one
final registry.resolve call. Do not reconstruct resource authority by searching
resolved URLs or relax existing slot hashes/ranges. Sentinel-leak retry must settle
first; every accepted re-composition gets fresh source coordinates/cmark markers.
A heading-only branch can add an unresolved render result retaining its registry,
settle leaked sentinels, validate/patch headings, then resolve once. Keep ordinary
no-heading route unchanged initially; all failures precede publication. This is a
material interface/order decision that must be in the binding plan and tested.

## Proposed shared policy (needs final review before coding)

1. Keep MarkdownEngine HeadingAnchorIndex as sole allocator/source identity. PR95
   fixes exact authored ID semantics using byte keys and preserves both decoded
   Unicode spellings; do not regress that with Set<String> in new adapters.
2. A read-only heading preparation in ExportService can build the index from one
   already-bound MarkdownDocument, exact source/lifetime/generation. No new parser
   or raw-HTML scanner in the app. If body has no literal '<', pure Markdown cannot
   emit authored DOM IDs; allocate directly without a full HTML DOM. Otherwise
   render source with existing cmark policy; only actual raw HTML requires bounded
   emitted DOM reservation/marker analysis. A '<' in code is conservative extra
   cmark work, not a raw-ID guess. Return immutable values, no DOM objects.
3. Preview and ordinary Export consume that same original-source index. App TOC
   registry uses linkedMarkdownList for it, retaining top-level-marker admission,
   escaped labels and once-encoded destinations. Preview failure preserves the
   authored marker with diagnostic; requested Export TOC failure is specific/fatal
   before any primary or companion output. No-TOC exports keep all existing limits.
4. Optional heading index on ExportRequest (default nil) lets the final composer
   verify cmark emitted headings through actual accepted splices and final DOM.
   Keep the current fresh export parse/FrozenExportParse; do not borrow Preview.
   App filters/replaces only its known TOC contribution, not arbitrary ranges.
5. Resolve Preview/Export SVG reservation differences before activation: generated
   ASCII heading bases are lowercase, so an uppercase ASCII SVG namespace family
   is provably disjoint. Choose a deterministic family avoiding every exact
   authored ID/name prefix, then namespace each accepted occurrence. Keep canonical
   cached artwork immutable and rewrite all existing href/CSS/ARIA references.
   This is a proposal, not permission to blanket-replace current prefix strings.
6. Full DOM analysis remains8MiB/4096explicit IDs when raw/opaque contributed HTML
   can alter target structure. To retain the binding pure-Markdown direct path,
   a strict, bounded fast-path certificate may admit only balanced harmless derived
   fragments with no IDs/names/rawtext/foreign content (ordinary TOC lists and exact
   simple math img output); unknown fragments use the DOM path, never bypass it.
   Prove this grammar before using it; rejecting unusual syntax must not alter
   ordinary output policy. Data-URI expansion happens after target validation.
   No full-DOM8MiB cap is imposed on ordinary no-TOC or pure Markdown just to pass.
7. App source binding can be shared with math through neutral internal names and
   compatibility aliases, preserving all existing exact model/editor/parse/lifetime
   and key-window checks. Heading session adds parser identity and owns one active
   analysis plus newest pending request. Cancellation/stale completion cannot
   publish an index or action. Index identity alone cannot authorize a replaced
   parser or closed/other window.
8. Fragment decisions distinguish own verified heading, unresolved internal,
   permitted existing external handling and denied. Compare complete current-file
   identity including query policy; decode fragment once. Raw-HTML-only targets
   stay unresolved in native Preview. Never send unresolved fragments to NSWorkspace.
   Controller uses single EditorSelectionSet/reveal, respects Reduce Motion and
   explicitly decides Preview-only/focus behavior before coding.

## Discriminating proof required

Valid TOC MUST produce real links and exact targets, including A/A/A-1, punctuation,
Unicode/CJK/empty/long labels, composed/decomposed authored IDs and legacy names,
front matter, code/HTML marker exclusions, repeated/mixed diagrams, authored ID
namespace collisions, templates, contribution rejection/sentinel retry and raw HTML
swallowing a heading. Pure >8MiB Markdown/no-TOC ordinary export must avoid new DOM
caps. Ambiguous/over-budget requested TOC must leave previous primary/companions
intact; Preview isolates the failure and preserves source. Resource slots must be
bound to patched final body, including images before/after headings and filenames
with %, #, ?, Unicode. Existing HTML/PDF lifetime/cancellation gates remain.

Native hosted tests should use the now-qualified actual app-shell harness, including
own-process AXApplication initialization. Invoke a real TOC link's native press
handler rather than directly calling the coordinator; assert correct source/Preview
heading and complete stale/wrong-window/caret/focus controls. Keep all deadlines
and positive controls. Owner visual/VoiceOver/signed/browser/PDF/QuickLook acceptance
remain separate. Run focused Debug/Release pure tests, actual native hosted tests,
complete locked CI and Release measurements before merge and checklist checkoffs.

## First implementation unit and stop boundary

Implement only the shared source-index preparation first. Its read-only result
contains the existing HeadingAnchorIndex and exact authored reservation values;
its initializer remains internal. It consumes one already-bound MarkdownDocument,
source/document/recovery/generation values and existing Markdown parse policy.
It runs on the concurrent executor, checks cancellation before/after synchronous
work, rejects source above the existing32MiB composition source policy and never
reads resources. An empty heading inventory requires no DOM analysis. Without a
literal '<' the direct index path needs neither cmark nor DOM. Otherwise existing
cmark rendering distinguishes actual authored HTML from escaped/code text. Raw
HTML uses existing marked-heading inspection/source mapping/publication validation;
raw-free output uses the direct index. The existing8MiB/4096ID DOM policy applies
only to actual analyzed markup. Any mismatch throws a specific preparation error;
the destination adapter will later isolate Preview or refuse requested Export.
No production route or link becomes active in this first unit. Tests must include
canonical-ID variants fixed by PR95, raw HTML swallowing headings, code/front
matter/escaped HTML exclusions, entity IDs/names, empty headings, source mismatch,
source/DOM budgets and cancellation. Compile actual tests and require hosted
execution. Do not call this feature completion or check either #10 row.

Before broad activation the fast-fragment proof and post-retry/pre-resource-slot
ordering must have discriminating tests. No unverified trusted flag may select a
fast path. A candidate strict grammar allows balanced ordinary list/link/text and
simple void img fragments only, with no id/name/rawtext/foreign content and no
unknown markup. Unknown syntax uses existing DOM analysis; it is not sanitized or
rewritten by this proof. Confirm exported actual normal TOC and math forms against
that grammar before binding it. Native TOC clicks should scroll the Preview;
select/reveal one heading range only when an editor is already attached, preserving
Preview-only layout and Preview focus. Revalidate the queued Preview scroll at
consumption, using a weak host closure and the same source/parser/window identity.
Source actions for math keep their existing explicit editor-mount behavior.

### Admission/work refinement before activation

A32MiB source can contain millions of tiny headings. Copying that full heading
inventory into a second navigation index would defeat the source-byte guard.
The new preparation therefore admits at most16,384generated headings, with a
specific heading-budget error before index allocation. This is a feature-local
initial bound, subject to final Release calibration; ordinary Preview/no-TOC
export keeps existing behavior. Add a real parsed over-count fixture. All source
scans and every synchronous preparation phase check cancellation before returning
an authoritative value or starting the next phase.

The existing allocator restarts duplicate suffix search at zero, making repeated
headings quadratic. Retain the next suffix per exact normalized base. The global
used-ID set is monotonic, so a previously rejected suffix cannot become available;
other heading families and authored reservations are still checked on every
candidate. Keep every generated ID and policy version unchanged. Compare exact
outputs with the frozen pre-change allocator, and record optimized repeated-heading
component timings before/after. Component timings are not whole-app acceptance.
