# Issue #117 — Destination capabilities, anchors and export identity

## Owner summary

Make TOCs navigate to the intended heading, make contribution destinations explicit, and ensure an export always uses one document revision from the initiating window. Preserve the native preview and ordinary HTML export's documented authored-markup policy; do not turn TOC work into an arbitrary HTML sanitizer or a new whole-document size restriction.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. See [README](README.md), [readiness review](READINESS_REVIEW.md) and original #125 history. E22 retains command-catalog consistency. This hand-off consumes its result and its selection/reveal APIs, not its active implementation branch.

## Reconciliation

ContributionRepresentation, TOCContribution, MarkdownDocument, native Preview BlockView and ExportCoordinator remain unchanged from the first review. Export supports HTML representations while native generic contribution admission rejects them. TOC is plain text; links are sent to NSWorkspace. Export's asynchronous code rereads mutable document/theme state and chooses ambient key windows for UI.

E22 now owns a cached `EditorTextSystem.selectionSet` because AppKit alone does not preserve every caret set. Native TOC/source actions must route through the completed controller single-selection/reveal path, which invalidates stale secondary selection state. Do not assign NSTextView.selectedRanges directly.

## Contract ownership and dependency order

Contributions owns ContributionDestination (nativePreview, htmlExport, pdfExport, quickLook) and representation-to-destination admission. Passive first-party HTML is static-destination-only; native specialized math/diagram views stay specialized. A user-settable trusted flag is not an admission mechanism. Unsupported contributions preserve source and return typed diagnostics.

MarkdownEngine owns HeadingAnchorIndex and its pure allocator. Its bounded authored-ID inventory adapter may depend on pinned SwiftSoup 2.13.9 as originally proposed, solely for non-executing HTML parsing/entity decoding. Confine parser objects to one worker and return immutable values; no fetching or unchecked Sendable DOM objects. The dependency must compile and pass the targeted parser corpus before use. Do not require DocumentPresentation just to build anchors.

The app owns ExportOrigin and immutable ExportSnapshot. Initially the snapshot carries the existing value-type Theme and effective post-E22 parse options. E23 later adapts that value into ResolvedPresentationPalette without changing snapshot timing or identity. This avoids the prior cycle where #117 required E23's palette and E23 required #117. #118 extends the SAME operation with progress/publication, and E23 moves only shared orchestration into DocumentPresentation.

## Heading index and deterministic allocation

Build one index from the immutable authored source/parse result. A heading record contains original-source identity, UTF-16 range/line, level, plain title and allocated fragment. Never identify repeated headings only by title or by index in a list of all rendered h-tags.

Anchor policy v1: parse plain heading text; normalize generated bases to NFC and locale-independent lowercase; keep Unicode letters/numbers/combining marks, `_` and `-`; collapse whitespace to `-`, remove other punctuation, trim hyphens and use section for an empty base. Initialize one global used-ID set with decoded authored IDs/named anchors, then try base, base-1, base-2, etc. This handles A/A/A-1 correctly. Bound generated IDs to 256 UTF-8 bytes with a grapheme-safe prefix and deterministic SHA-256-derived suffix, reserving suffix space; never use randomized Swift hashValue. Include allocator/Unicode policy version in reproducibility records.

Reserve authored HTML IDs; never rewrite them to make room. An authored `<div id="overview">` followed by `# Overview` produces the generated heading overview-1. Explicit IDs retain exact DOM string semantics, not generated-slug lowercasing/NFC. Native Markdown Preview must not silently route #overview to the different heading when it does not render the raw HTML element.

Index identity includes document/recovery lifetime, source generation/content identity and parse policy. Identical source yields identical allocation; insertion of an earlier duplicate may change later suffixes. This is deterministic naming, not permanent cross-edit identity. Generated TOCs use the allocated index and cannot introduce another heading inventory.

## Bounded raw-ID inventory and failure containment

Inspect authored raw-HTML blocks/inlines in correct parser context, excluding code/front matter/escaped markup. Coalesce fragments when a tag crosses runs. Use explicit HTML mode, not XML auto-detection. Include quoted/unquoted/entity IDs, comments/rawtext, legacy named anchors and malformed structures in the corpus. Static generated contributions/template IDs participate in collision validation without masquerading as authored headings.

After cmark emits the body and before resource-data-URI amplification, verify each generated target is uniquely the expected authored Markdown heading and each generated TOC link points to it. Do not reserialize the HTML through the validation parser. Map cmark source locations through front-matter offsets and SourceMap; reject a mismatched heading record instead of zipping all `<h1>`–`<h6>` elements. Resource rewriting after validation must not create/remove IDs.

Corrected failure policy:

- Documents without generated TOC/heading-link functionality do not acquire a new global DOM gate. Ordinary no-TOC HTML export retains existing admission limits and raw-markup behavior.
- Normal valid TOCs within the supported policy MUST be navigable. Tests may not accept source fallback for those fixtures.
- When malformed/ambiguous authored markup prevents a reliable generated target, ordinary HTML export must not claim a working generated TOC. Return an explicit anchor diagnostic and preserve prior output when that requested feature cannot be produced. The failure is specific, not a generic invalid-document claim.
- Quick Look and native Preview isolate the failed TOC contribution: preserve readable authored marker/source with a diagnostic and continue the rest of the document. They must not fail/blank the whole preview because the TOC cannot be admitted. Generated heading navigation is not published from an unverified index.
- A raw-HTML-only target that native Preview does not display is an unresolved internal target, not an external-navigation fallback.

The earlier unconditional 8 MiB final-HTML analysis ceiling is REMOVED. Use a distinct anchor-analysis policy: initially 8 MiB of actually analyzed markup and 4,096 explicit IDs, subject to #118's documented calibration. Exceeding that sub-budget follows the destination-specific contribution policy above; it is not a silent reduction of normal export's 32 MiB source/128 MiB prepared-body ceilings. Pure Markdown takes the direct node/index path without a full HTML DOM. Bound bytes, depth/work where the parser supports it and queued analysis; input-byte bounds alone do not establish a hard parser-time/RSS guarantee. A failed parser probe requires a focused alternative before claiming this policy is implemented.

Ordinary authored JavaScript may deliberately alter its own exported DOM later under that destination's existing policy; static TOC validation is not a promise about arbitrary subsequent scripts. Native Preview/Quick Look enable no such authored execution.

## TOC serialization and navigation

Retain top-level-paragraph-only [TOC] admission, nested heading hierarchy and no-heading placeholder. Escape labels as Markdown, encode fragment destinations once and HTML-escape attribute values at serialization; these are separate operations. Literal percent/entity/quote/CJK cases must reach the exact ID.

PreviewLinkAction is internalHeading(record, identity), unresolvedInternal(fragment), permittedExternal(URL) or denied. Bare fragments and verified same-current-file URLs are internal; compare complete file identity/path semantics rather than basename. A different query is not silently treated as the current document. Decode fragment once, reject malformed escapes/controls/unsafe schemes and never send unresolved internal anchors to NSWorkspace.

The document controller owns the navigation closure. Validate lifetime/generation again when executing, use existing scroll/source navigation, respect Reduce Motion and preserve focus deliberately. Rendering itself must not alter editor selections. Quick Look uses static HTML fragment links and no app controller.

## Export origin and snapshot timing

Resolve/capture the origin synchronously on MainActor at command dispatch and reserve its existing reentrancy guard before spawning async work. Store the window/controller lifetime, document ID/recovery epoch and operation ID. Menu validation can inspect focus; execution never retargets to whichever window later becomes key.

Present the panel on that exact origin. After acceptance, reread the live document from the captured controller and verify it is still the same logical lifetime and exportable. Do not use the stale FileDocument value captured before the panel. Obtain its source through the normal completed editor-publication boundary, then freeze source/generation, URL/resource grant, Theme, effective parse options, target policy and identity ONCE before renderer awaits. A newly substituted document cancels. A later edit is allowed but cannot splice itself into the frozen request.

Parse, anchor analysis, contributions and ExportRequest all consume this snapshot. Do not reread live source/theme/generation after suspension or consult Preview's stale parse. The root lease preserves actual admitted source access even if Save As changes the live window later. Destination collision rules belong to #118, not this source snapshot.

Origin closure requests cancellation and revokes subsequent sheets; it must not move a completion/error alert to another window. Release the operation guard exactly once for panel cancellation, origin loss, renderer failure and completion. Callback bridges cannot retain a closed window indefinitely solely to show stale UI.

## Extra parse disposition

Separate the fresh MarkdownEngine parse, optional ID analysis, cmark pass, contribution rendering and serialization in Release timings. Reuse the same immutable MarkdownDocument/index within an export whenever exact source/options identity agrees; do not parse identical MarkdownEngine input twice. Keep the distinct cmark rendering pass. Record absolute and relative costs on 1 MiB ordinary text and representative technical/raw-HTML documents; no 'negligible' assertion without data. A different rendering engine is not part of this issue.

## Implementation units and discriminating tests

A. Pure destination/anchor values, allocator and bounded raw-ID adapter. Probe real pinned HTML parsing/context with exact browser fragment outcomes; no generic sanitizer or network API. Tests: A/A/A-1, punctuation-only, combining/CJK/long headings, locale changes, front matter, raw ID/name/entity collisions and raw markup swallowing a heading.
B. cmark IDs/TOC output, target validation and native routing. Test valid navigation, unchanged authored bytes, ordinary no-TOC large export preservation and per-destination ambiguous/over-budget fallback. #113 consumes the same index, not a second slugger.
C. Explicit ExportOrigin/snapshot. Suspend controlled parse/render jobs; edit A, focus B, change A's theme, Save As, close A and cancel. Assert one snapshot and no B-directed sheet. Include current E22 primary/secondary caret invalidation on navigation.
D. Consume final E22 command-catalog proof; run current menu/palette consistency with explicit exclusions. No edits to current E22 are requested.
E. Release phase measurements, full regression and actual TOC/export UI evidence through #88.

Allowed areas: MarkdownEngine/Contributions values and tests; Preview internal-link adapter; ExportService node/TOC code; app export-origin integration and catalogs. No FileStore safety weakening, editor replacement or post-E22 feature expansion. Run serial format/strict lint, affected/full package/app suites and Release build. Stop on wrong-target navigation, unbounded parser behavior, weakened source preservation or necessary unplanned dependencies.

## Review disposition

Second review resolved the palette dependency cycle, stale pre-panel document capture, direct NSTextView selection writes, indiscriminate DOM analysis, silent export-cap reduction and Quick Look's contradiction with fatal TOC errors. The original collision decision remains, but now has destination-correct failure semantics. All issue areas still require executed evidence; E22's registry subset alone cannot close #117.

## Rebaseline 2026-10-09 — contributed SVG identifiers

The heading allocator reserves authored IDs, but contributed IDs were only detected afterwards, and cached diagram artwork has no per-occurrence namespace. Graphviz emits `graph0`/`node1`-style IDs and leaves embedding uniqueness to the caller; an `[TOC]`, a heading `graph0` and a simple DOT diagram can therefore lose the requested TOC anchor or yield an ambiguous one, and a repeated cached SVG or page-local Mermaid counters duplicate IDs. Pipeline today: Graphviz SVG is emitted inline, the sanitizer preserves IDs, custom HTML is emitted as-is.

Contract: the assembly step owns a deterministic per-OCCURRENCE SVG namespace (rewriting `id`, `href`/`xlink:href` fragments, `url(#…)`, CSS selectors and accessibility `aria-*` references together) that is disjoint from authored, heading and template IDs and is allocated BEFORE heading IDs are finalised. Cached canonical artwork stays immutable. Tests: heading `graph0` + DOT, explicit DOT IDs, repeated cached occurrences, mixed engines, separate Mermaid workers/restarts. Duplicate composition IDs and the TOC conflict are source-confirmed; native visual symptoms are not claimed reproduced.

## Rebaseline 2026-10-22 — coordinates after derived-content splicing

The earlier direction to compare a heading's original line with cmark's line
assumed that both parsers saw the same body. That assumption is false when
Export replaces an accepted contribution with an inline sentinel or a
blank-line-delimited block sentinel. An earlier replacement can shift all
later cmark line/column positions, including after the existing leaked-sentinel
fallback re-composes the body. The isolated top-level heading probe did not
exercise this pipeline.

When generated-heading analysis is requested, Export must carry a bounded
original-body-to-spliced-body coordinate map from the exact *accepted*
replacements it actually applies. Ordinary no-TOC export does not build this
map or hash its body again. An offset inside a
replaced source range has no faithful output coordinate and must be reported
as unmappable; before/after offsets map by the accumulated UTF-16 length delta.
Build a fresh map for every re-composition, including the leaked-sentinel
fallback. Bind the map to the original body and collected cmark heading
locations to the exact transformed body with stable content fingerprints;
otherwise a same-shaped result from another render could be misidentified.
Front matter is already removed from the body handed to cmark, so
convert an index heading's original line through `bodyLineOffset` before using
the map. A later heading match must verify one generated cmark heading at the
mapped line and expected level and reject any ambiguous or structurally changed
case. Heading ordinal by itself, raw authored h-tags and spoofable `data-sourcepos`
attributes are not identity evidence. Keep generated links disabled until the
marker/target and final DOM checks also pass their hostile fixtures and review.

This correction changes no normal no-TOC HTML output or dependency pin. Its
first implementation unit is the pure coordinate map with tests for multiple
inline/block substitutions, Unicode/CRLF, replacement boundaries, rejected
contributions and front-matter offsets. It is not acceptance of generated
navigation.

## Rebaseline 2026-10-22 — marked emitted headings and final DOM check

The pinned cmark probe established that a custom inline first child can mark
an ordinary generated heading without changing its output after the comment
is removed. An authored comment equal to a predictable marker disproved a
document-wide replacement approach. The next implementation unit therefore
uses a fresh one-render marker value, attached only to cmark heading nodes.
The marked output is private intermediate data: it is never sent to the
ordinary exporter or published as HTML.

For a bounded anchor-analysis request, parse the **emitted** marked HTML as a
body fragment with pinned SwiftSoup 2.13.9. Require each marker exactly once
as a direct child of the expected heading, and reserve DOM IDs plus legacy
`a[name]` values from that emitted tree. Allocate fragments against those
reservations; verify the source index against the spliced-body cmark locations.
Patch only each uniquely matched literal `<hN><private-comment>` span to an
escaped `<hN id="…">`, preserving every other authored byte. Parse the actual
patched HTML again and require the same element order, one target per
fragment, and the target at the originally marked heading's position. A
malformed structure, duplicate/private marker, changed source/render identity,
wrong reservation set, or analysis-budget failure returns no generated links.
The current candidate caps each analyzed HTML string at 8 MiB and the
explicit ID/name inventory at 4,096 entries; it does not impose these caps on
ordinary no-TOC export.

The marker/DOM code is opt-in and **not wired into export or Preview** yet.
The first local corpus covers raw/tagfiltered IDs, legacy named anchors,
authored marker copies, malformed HTML, front matter, block/inline splices and
both analysis budgets. It does not prove per-occurrence SVG ID namespacing,
normal linked-TOC serialization, native navigation, final-template IDs,
Release parser memory/cost, or signed/owner-observed behaviour. Independent
review must inspect these boundaries before activation. The SwiftSoup pin,
licence, generated notices and software bill of materials are part of the
same candidate, with no production dependency re-resolution beyond that
one immutable package.

## Rebaseline 2026-10-22 — opt-in SVG namespace candidate

The export assembly now has an opt-in per-contribution SVG ID rewrite after
derived HTML sanitization. The default remains off, so ordinary export output
is unchanged. The candidate isolates repeated cached SVG occurrences, their
plain `href`/`xlink:href` fragments, paint `url(#…)` references, simple CSS ID
selectors and accessibility ID lists. An ambiguous ID or unsupported SVG/CSS
form returns a diagnostic and leaves the authored fence in the opt-in path.
Its focused pipeline tests show that two reused `graph0` diagrams do not steal
the `# graph0` heading target. Native preview links still use their existing
route; no generated heading link is exposed.

This is a staged parser, **not activation evidence**. Before enabling it,
review CSS nesting/escapes and encoded CSS references against real Graphviz,
D2 and Mermaid output; prove namespace disjointness from final-template IDs;
measure adversarial time/memory bounds; and
obtain independent security and native visual review. At this checkpoint the
conservative CSS path rejected at-rules, comments and quoted strings instead
of publishing a partly rewritten diagram. Linked TOC serialization,
destination-specific failure behavior and signed owner-observed navigation
remain open.
Entity-encoded SVG attribute IDs/references are decoded before matching, and
the opt-in emitted-DOM check rejects a collision with an authored ID that
duplicates the SVG namespace. These checks do not cover every CSS escape or
the final document template.

## Rebaseline 2026-10-22 — actual renderer CSS and complete-template probe

The first CSS scanner rejected actual D2 and Mermaid output. A bounded
follow-up admits the forms those bundled renderers emit: quoted font values,
`@font-face` data-font URLs, `@keyframes`, grouped CSS rules and Mermaid's
quoted attribute suffix selectors. It balances blocks and separates
declarations outside quoted values and URL parentheses. Unknown at-rules,
comments, CSS escapes, malformed blocks and quoted fragment selectors still
reject the opt-in diagram; the authored fence remains available. The default
export route remains unchanged.

The newly admitted font rule accepts only local `#id` URLs and embedded WOFF
data-font bytes. A remote, file or relative CSS resource URL rejects the
opt-in diagram, including when the SVG has no IDs or the URL is in a paint
attribute, preserving the offline contract for this new path. D2's bundled
`data:application/font-woff` is covered by the real-renderer test.
Resource-bearing SVG element links (`image`, `use`, text paths and similar)
must also resolve to an ID inside the same diagram. The opt-in path rejects
`src`, `srcset`, `poster`, `background` and CSS image functions inside SVG;
it still permits an interactive `<a href="https:…">`
link, which opens only by a user action. This distinction is necessary because
the pre-existing sanitizer permits HTTPS for clickable links.

One serial package test renders representative actual Graphviz, D2 and
Mermaid diagrams in WebKit, sanitizes them, rewrites their IDs and references,
and compares the original and rewritten canvas PNG bytes. All three passed
on CORTANA. The D2 fixture includes four unresolved fragment references in
CSS rules without corresponding IDs; this corpus proves visual parity for the
sample, not that every D2 stylesheet rule has an internal target. A separate
test parses the assembled built-in document template, with and without the
PDF policy header, and finds one unique emitted heading target and one
distinct SVG ID. The current fixed template emits no competing ID. These
tests do not prove that a future template or arbitrary additional head markup
cannot add one; collision validation must use the actual final output at
activation.

The opt-in dense-stylesheet Release package probe on CORTANA rewrote
1,116,064 input bytes to 2,124,093 output bytes in 0.357 seconds, with a
single SwiftPM build job. The command's 797 MB peak resident set includes
the compiler and test host; it is not a per-operation memory ceiling or
complete app measurement. Independent security review,
broader adversarial CSS/reference handling, native visual/navigation checks,
linked TOC serialization, and destination-specific failure behavior remain
activation gates. No generated link is exposed by this checkpoint.

## Independent review 2026-10-22 — SVG/CSS admission remains gated

An independent review of `dc02e478` requested changes. Its P1 findings were
that inline CSS escapes/comments could hide a resource URL from literal
`url(` scanning, an accepted at-rule prelude could contain an earlier statement,
and HTML entity decoding could make CSS source and browser interpretation
disagree. The follow-up rejects escapes, comments and residual `&` entities
in every SVG CSS entry point, admits only one exact supported at-rule before
each block, and retains source-fence fallback on rejection. A WebKit package
fixture loads the actually assembled fallback with an in-memory custom URL
scheme handler. No resource request occurred for the rejected payloads; a
positive-control image did reach that handler. It makes no external request.

The same review found P2 isolation gaps: unresolved paint URLs, bare CSS ID
selectors and accessibility ID references can bind outside the occurrence;
exact-match ID attribute selectors change meaning when IDs are renamed;
and `content:url(#id)` needs token-aware rewriting. Separate standalone SVG
canvas comparisons do not prove isolation in a composed HTML document. These
remain open for a subsequent bounded change and browser fixture. The reviewer
has not approved activation or run native navigation tests. The generated
link route stays disabled while these findings, linked TOC integration and
signed owner-observed acceptance remain unresolved.

## Subsequent SVG isolation regression checkpoint

The next review confirmed the direct CSS/resource bypasses closed at
`522c0443`, but did not approve SVG isolation. Failing-before regressions
reproduced a decoded reference selecting a synthetic root, sibling selectors
escaping an SVG, root class selectors losing their effect, and animation
rewriting that corrupted negative delays and `!important`. The opt-in parser
now reserves synthetic IDs against decoded markup, rejects unowned interactive
fragments, accessibility references and CSS ID selectors, rejects selectors
whose scope or root semantics cannot be preserved, and preserves signed
animation durations and importance while rejecting `var(...)` animation
values. Strict format/lint and focused serial Release tests passed, including
the existing real Graphviz, D2 and Mermaid canvas comparisons. The ordinary
export path and generated heading links remain unchanged and disabled.

This is not activation evidence. Unresolved paint `url(#id)` and animation
names still need final-document ownership proof or safe fallback. D2's real
output contains unresolved CSS paint references, so simply rejecting every
unknown fragment would break a supported diagram. `@font-face` and custom
font-family names remain document-global; the real D2 fixture uses both.
The complete emitted document/template still needs ownership validation,
source-to-rendered identity binding, controlled network/file-load testing,
and the handoff's native navigation, Release and signed owner-observed gates.

## Embedded font follow-up

A failing-before Release test showed that an accepted SVG `@font-face` family
kept its original document-global name. The opt-in CSS pass now prefixes a
supported embedded WOFF family and its references within the same style block;
unsupported local-font sources, cross-style references, font shorthand and
inline family references preserve the authored diagram source instead. A
separate D2 stylesheet without font-family references remains admitted, as do
its inline font-size declarations. The focused serial Release parser and real
Graphviz, D2 and Mermaid pixel tests passed on this local candidate. This
limits accidental font-name collisions but does not by itself prove that
authored final-document CSS cannot deliberately name the predictable prefix.
The final-document ownership and activation gates above remain open.

The local Release package probes after the font change processed a 1,116,064
byte dense stylesheet in 0.754 seconds and a 1,131,120 byte technical document
in 0.094 seconds parse/render, 0.007 seconds inspection and 0.103 seconds
patch/validation. These are package-host timings, not full-app or memory
ceilings. The previous `61513b06` hosted run ended with process signal 11 in
the package-test step, without a recorded failed assertion or crash stack;
later log lines were buffered. Its exact cause is unproven, and an exact final
candidate needs successful hosted validation before any merge.

## Follow-up review of `ee277a8d`

The next independent source review found three more parser errors: embedded
font-family lookup was case-sensitive even though CSS family matching is not;
two face-bearing style blocks could refer to each other's family without a
rewrite; and the animation scanner changed a valid leading-dot negative
delay (`pulse 1s -.5s`) into an invalid name. `calc(...)` in animation values
was also admitted without a supported parser. Failing-before package and
WebKit tests reproduced these cases, including a computed delay of `0s`
instead of `-0.5s`.

The disabled SVG path now folds supported embedded font-family names to one
case, rejects a family not declared in that same style block, preserves valid
leading-dot negative delays, and rejects unsupported animation functions.
Its second CSS pass also requires animation names to match a keyframe in the
same stylesheet; unknown names and inline animation references fail closed.
The focused serial Release suite again matched real D2, Graphviz and Mermaid
canvas output and WebKit computed the valid delay as `-0.5s`. The ordinary
export path and generated links remain unchanged. Exact-head hosted checks,
independent re-review of this new checkpoint, and the full activation gates
remain necessary. The prior `ee277a8d` hosted run passed package, app and
pin checks; that does not explain the older `61513b06` signal-11 crash.

Unresolved paint fragments are still predictable and can bind to an authored
outside ID. The deterministic prefix can also be named deliberately in raw
authored stylesheet rules. The accepted handoff requires checking ownership
against the actual assembled document, including its head/template, without
adding a global DOM gate to ordinary no-TOC exports. The writer currently
returns a non-optional complete string, so the opt-in failure route needs an
architecture review before this boundary is wired into export.

## Fail-closed resource ownership checkpoint

The next disabled-path review found that a quoted custom `@font-face` named
`"serif"` could be mistaken for an unquoted generic `serif` reference. The
limited embedded-font admission now rejects reserved generic and CSS keyword
family names. It also rejects unsupported fallback lists such as
`Demo,sans-serif`; this is a narrower safe subset, not complete CSS font
support.

Every actual local `url(#id)` token in an SVG presentation attribute or CSS
declaration must now name an ID collected from that same SVG. Entity-decoded
attribute fragments follow the same rule. Unsupported or unresolved tokens
reject the entire derived contribution: Export retains the authored source
fence and records an error diagnostic, without quietly dropping a declaration
or synthesizing a target. A quoted CSS content string containing `url(#id)`
remains text. Repeated owned IDs are still rewritten per occurrence.

The representative D2 renderer emits unresolved paint references, so this
opt-in path currently falls back to its source fence for that diagram. Native
WebKit fixtures still show unchanged canvas pixels for admitted Graphviz and
Mermaid SVGs. This is an explicit compatibility limit to resolve before
activation, not a reason to allow references to authored outside IDs.
Generated links and SVG namespacing remain unwired in the normal export path.
The assembled document, including template/head IDs and authored CSS
keyframes/font names, still needs a complete ownership check. Signed/native
navigation and exact-head hosted validation remain separate gates; the older
unexplained signal-11 run is retained as unresolved evidence.

## Private complete-document ownership receipt

The next opt-in unit marks each namespaced SVG with a one-render comment pair
and captures its root ID and owned-ID inventory. After body, head and template
assembly, it parses the **complete exact HTML**. Every generated ID must occur
once inside its marked SVG; resource, fragment and accessibility references
must resolve inside the same subtree. It inventories rewritten keyframes and
case-folded embedded font families, rejecting matching authored definitions
outside the SVG. Outside inline styles that name a generated prefix, escaped
CSS definitions, imported stylesheets and linked stylesheets fail closed.

The receipt hashes the marked complete document and the marked contribution,
and retains the exact marker/root/owned-ID inventory. Publication rejects a
different inventory even if the marked contribution bytes are unchanged; a
regression showed that otherwise forged marker metadata could remove unrelated
comments and leave private markers in published HTML.
Private comments must be adjacent to their SVG in the parsed tree; a raw
open-tag stack check also rejects cases where HTML parsing moves the SVG and
both comments out of a malformed container together. Publication removes the
comments in one pass and parses the resulting exact bytes again, requiring
the same roots, ID/reference edges, definitions, subtree shape and ancestor
locations. A changed head, template or recomposed fragment cannot reuse the
receipt. The test-only caller can check the returned publication hash before
writing; normal ExportHTMLWriter remains unchanged.

This is still disabled groundwork. It does **not** yet route a final-assembly
failure back through ExportComposer's source-preserving re-composition or bind
the receipt to the actual file/PDF writer. That failure path and source-to-
rendered identity remain activation gates. Analysis is limited to 8 MiB of
complete HTML, 64 marked SVG roots and 4,096 generated IDs; documents beyond
those limits must keep their authored diagram source in the future opt-in
route. A companion linked stylesheet is a separate byte stream and is
currently rejected until its bytes can be inventoried and bound. The normal
no-TOC export path has no new size limit or changed output.

The bounded Release package probe used 1,006,567 assembled HTML bytes and 16
marked SVGs. It measured 5.54 seconds with one raw-tag scan per SVG and 2.84
seconds after making that scan single-pass. These are package-host timings,
not full-app, WebKit-process or peak-memory figures. The admission budgets
and performance need review on the eventual combined publish path.

## Outside CSS ownership correction

A subsequent source review found that checking SVG-local references alone does
not contain computed paint. An authored head rule such as
`svg rect { fill: url(#outside) }` overrides a namespaced rectangle's
`fill="url(#owned)"`; a custom property inherited from `:root` has the same
effect. WebKit regression fixtures capture both the computed outside target
and blue rendered pixels before the validator correction.

The disabled validator now rejects every nonempty stylesheet outside a marked
SVG except one exact head style emitted by the built-in export writer. That
style is derived only from colour-valued Theme variables and the bundled
structural CSS; the structural bytes are pinned to an audited SHA-256 and the
writer's newline wrapper is compared exactly. A changed bundle needs renewed
review before admission. Authored body styles, inline style attributes outside
the marked SVGs, a second head style, and linked stylesheets fail closed in
this opt-in route. Empty head styles are inert and remain accepted for tests.
The normal export path is still untouched. These conservative rejections need
source-fence fallback when the route is eventually wired; they do not permit
activation or establish native acceptance by themselves.

A further reviewed inheritance case uses no stylesheet: an authored outer SVG
with `fill="url(#outside)"` can wrap a generated inner SVG whose rectangle has
no explicit fill. The validator formerly counted no inner resource edge, while
WebKit inherited the outside gradient and rendered blue pixels. The opt-in
receipt now rejects any marked root nested beneath an SVG ancestor. Such
compositions must preserve their authored source fence in the future route;
ordinary export is still unchanged.

## Proposed exact-byte publication boundary for review

This is a proposal for the remaining opt-in route, not an activated contract.
The user outcome is that a generated TOC or namespaced diagram is published
only when its final HTML points to the intended element; an unsupported diagram
remains readable as its authored source. Ordinary exports without the opt-in
feature continue through the existing writer and budget policy.

Capture the initiating model/window as ExportOrigin when the command opens its
panel. After the panel returns, revalidate that same model and document
lifetime, then freeze text, source generation, current value-type Theme,
effective parse options, document URL and selected destination together on
the main actor before the first parse/render suspension. A close or identity
replacement before this freeze cancels without writing; focus on another
window never redirects a panel or export. Later edits and theme changes do not
change that frozen export. Explicit task cancellation is checked after each
await and immediately before any file or WebKit publication.

After the existing sentinel-leak retry settles the accepted contribution set,
carry its source ranges and marked SVG roots with that exact render. Build the
destination-specific complete HTML once: standalone embedded CSS, self-
contained HTML after image data-URI expansion, or PDF input with its CSP head.
Create the final fragment identity from the actual post-expansion body and the
same root inventory. The assembled-document inspector either returns one
marker-free publication bound to the exact HTML bytes or rejects it. A linked
stylesheet is currently rejected because its separate bytes are not in the
receipt. Failure excludes only affected opt-in contributions, adds a useful
diagnostic, and repeats composition once with fresh source coordinates and
resource resolver; if safe generated TOC navigation still cannot be produced,
the destination-specific failure policy above applies. No output or companion
asset may be written before this decision.

The immutable receipt may be checked repeatedly only against the same marked
document, final fragment inventory and publishable byte string. Reuse for a
different destination, CSP, asset-directory name, recomposition or source
generation fails identity checks; there is no consumable mutable token. A
second export builds its own receipt from its own frozen snapshot. Cancellation
after companion creation but before HTML primary promotion follows the
existing primary-last durability rule: owned content-addressed assets may
remain, but no unvalidated primary is exposed.

The HTML writer should consume the immutable validated publication directly,
checking the digest of the bytes it is about to promote and writing companions
first, primary HTML last. It must not rebuild the template after validation.
The app's PDF adapter currently builds its own self-contained/CSP string, so
cross-module publication needs a small immutable export value carrying those
validated bytes and source generation; the adapter would load exactly that
value into its locked WebKit view. It must not add or rewrite CSP afterward.
The proposed public surface is one read-only `ValidatedExportHTML` value with
an internal constructor, UTF-8 bytes, digest and snapshot generation, plus a
PDF adapter entry point that accepts that value. The existing `prepare` and
ordinary `exportHTML` APIs keep their current behavior. Whether the app should
receive this value directly or through one opt-in ExportService operation is
the material interface choice for review; callers cannot forge it from an
arbitrary `PreparedExportDocument`.
This public interface and the bounded re-composition loop require independent
architecture review before implementation. Tests should cover a changed head
or body after inspection, linked-CSS rejection, data-URI expansion, PDF CSP,
source-fence fallback, no file side effects on rejection, and exact bytes at
the HTML and PDF consumers. Native owner-observed navigation and signed app
evidence remain separate gates.

### Disabled publication implementation checkpoint (22 October 2026)

The reviewed interface choice is one opt-in `ExportService.exportValidatedSVG`
operation. It recomposes at most once after an assembled-document rejection,
then returns source-preserving output or an error. Its internal constructor
produces an immutable `ValidatedExportHTML` carrying final UTF-8 bytes, source
identity, destination, resource inventory and diagnostics. The HTML writer
stages content-addressed companions without replacing existing assets and
promotes the validated bytes last. The PDF adapter accepts the same bytes
without rebuilding its CSP or template. Both publication paths check an
app-owned lifetime lease at the final synchronous promotion cutoff.

This path has no production caller yet. The initiating window/document capture,
post-panel freeze and identity-change revocation described above still need
app integration and native acceptance before activation. The available app
test verifies the PDF adapter's exact HTML input conversion and destination
binding; it does not run a WebKit print operation or prove a PDF was produced.
Package tests cover exact HTML bytes, Unicode/data URIs, source fallback,
asset conflicts and symbolic links, cancellation after staging, and
fail-closed navigation policy. Ordinary export APIs and visible behavior are
unchanged. The earlier hosted signal 11 remains an independent investigation,
and this disabled checkpoint is not a signed runtime or release acceptance.

The next review found that `#`, `?` and literal percent escapes in an output
filename made a companion image URL resolve to the wrong path. The corrected
path percent-encodes the single assets-directory component before cmark or
HTML escaping; tests resolve the emitted image URL back to the exact staged
manifest file, including Unicode names. The disabled HTML writer now opens
the selected parent and assets directories without following their final
symlinks, stages files relative to those descriptors, checks inode identity
before promotion and atomically renames the accepted primary relative to the
opened parent. Tests replace the assets pathname during and after staging,
and verify neither replacement redirects a write or publishes new HTML.
The primary HTML is now written and fsynced to an exclusive temporary inode
before the final parent, companion and temporary-name checks. The lease cutoff
then checks and renames without suspension. A deterministic replacement of the
temporary name before that check rejects publication and leaves the prior
primary intact. This narrows the final check-to-rename interval; it does not
make primary and companions an atomic multi-file transaction. A separate actor
with write access to the chosen directory can still replace a companion,
parent path or temporary name after its last check, during that interval or
after return. This disabled path assumes a destination that is not being
concurrently mutated by an adversary. The URL tests use Foundation resolution,
not an actual WebKit resource load.

WindowController now holds weak registrations for opt-in export leases. A
captured origin freezes the current document text, generation, URL and theme
only after a panel would return; later edits do not change that value.
Document replacement revokes the lease synchronously before the old identity
is unpublished, and window close revokes it too. A focused native app test
covers freeze timing and pre-publication revocation. The ordinary export flow
remains unchanged.

The next disabled operation captures the key window and reserves its export
guard synchronously before spawning work. Its test seam accepts a destination
from that captured window after an asynchronous panel interval, then freezes
the live source, generation, URL and theme. One Markdown parse supplies both
contributions and composition; the parse cache checks exact UTF-8 source
bytes, revision and options. The same lease follows the request through
HTML/PDF publication, and guard cleanup runs on cancellation and failure.
Native unit tests use an explicit captured controller because a headless test
host does not reliably provide `NSApp.keyWindow`; they cover focus/theme
changes, later edits, Save As identity replacement, close across an await and
revocation before publication. A separate native `WKWebView.loadFileURL` test
loads the disabled standalone HTML output and decodes its real companion PNG
from filenames containing `#`, `?`, a literal `%23` and Unicode. This adds
browser evidence beyond Foundation URL resolution; it does not test an actual
save-panel selection, signed sandbox access or PDF printing. The operation has
no production command yet. Signed owner observation and generated-link
activation remain open.

The next disabled checkpoint adds a real `NSSavePanel` helper bound to the
captured document window. It offers HTML with embedded CSS, self-contained
HTML and PDF; linked CSS remains unavailable because its separate bytes have
no validated receipt. A one-shot, main-actor reply settles a user cancel,
origin-window close notification or task cancellation without redirecting to
a newly focused window or leaving the export guard set. The ordinary panel
keeps its existing choices. Unsigned native tests mounted the real sheet,
switched focus, cancelled it, posted an origin-close notification and cancelled
its task; the focused suite and locked Release app build passed. Posting a
close notification is a controlled lifecycle probe, not proof that macOS lets
an owner close a tab with a sheet open. No production command invokes this
helper. Real key-window command dispatch, accepted Save-panel selection,
signed resource access, PDF output and owner-observed behavior remain gates.

Independent review found that a captured origin could be revoked after the
synchronous command capture but before its spawned task began. The disabled
operation now checks the lease immediately before invoking the chooser, on
the same main-actor turn. A native regression closes the origin before the
task starts and verifies that no sheet is presented and the export guard is
cleared. The real-sheet cancellation test also waits for physical detachment
from the originating window. These checks do not establish accepted panel
selection, signed resource access, PDF output or owner-observed navigation.

For the remaining native panel journey, a separately compiled Release
acceptance build uses `ISSUE117_NATIVE_ACCEPTANCE`. Only that build has a
labelled File-menu entry calling the disabled validated operation and a
bounded diagnostic log. It requires an explicit isolated `-UITesting` launch
with disposable files, so it does not restore or write the owner's ordinary
session/recovery state. Normal Debug and Release builds compile out both
entries; this is not generated-link activation or a production export path.
The retained app, fixtures, launcher and owner checklist are in
`_cleanup-archive/issue117-native-acceptance-2026-10-22/`. Actual accepted
Save-panel publication, browser companion loading, signed sandbox access,
PDF printing and generated-link navigation have not been inferred from the
prepared artifact.

The first normal-build hosted run of this test-only entry failed the command
catalog's source scan: it counted two commands inside the acceptance-only
compile condition as shipping commands. The scan now excludes that specific
conditional block and asserts both labels are absent from the shipping
inventory. The focused catalog suite passed locally against the pinned
dependencies; normal exact-head hosted validation is still required.

## Rebaseline 2026-10-26 — ordinary Export snapshot and publication

### Owner summary

Choosing Export in document A must never save document B after focus moves, mix
two edits or themes, or publish a file after A closes. A saved document's
relative images must come only from its own admitted directory. This corrects
the ordinary HTML/PDF operation; it does not enable the separate validated-SVG
route, infer folder permission from an open file, or add another chooser.

### Current implementation boundary

The ordinary command starts an asynchronous task before it captures a window.
`ExportCoordinator` then consults the ambient key/main window, attaches its
sheet to the ambient key window, holds a pre-panel `FileDocument`, reads the
theme later, and sends errors to whichever window is current. Its contribution
parse and `ExportComposer` both use default Markdown options even when E22's
editor has block directives enabled. `ExportRequest.documentURL` is also used
as a resource root: `ExportResourceResolver` derives its parent pathname and
later reopens children by path. A frozen URL is not a retained directory grant
or a pinned directory identity. Ordinary HTML primary promotion has no
lifetime cutoff, and ordinary PDF calls its adapter without a lease. The
disabled validated operation has useful identity and publication primitives,
but its distinct feature policy is not activated by this correction.

### Binding implementation order

1. At command dispatch on the main actor, resolve one visible document window,
   reserve its existing per-document Export guard, and capture its controller,
   document ID, recovery epoch and operation identity before starting a task.
   Present and dismiss the sheet on that window only. Cancellation, origin
   loss and errors release the guard once; alerts never retarget another
   window. A pre-panel replacement cancels before reading or publishing.
2. After panel acceptance, revalidate that origin and read the completed
   editor-published document value. Freeze source, generation, file URL, the
   current Theme, `MarkdownParseOptions` derived from E22 settings, format,
   style and destination together. Add a value parse-options field to
   `ExportRequest` (defaulting to the former policy for other callers), and
   pass the frozen value to both the contribution parse and
   `ExportComposer.parse`. Do not consult live window, text, theme or options
   again during rendering.
3. Open and retain an explicit source-directory capability from the saved
   document's parent under the process's existing access at freeze time.
   `ExportRequest.documentURL` remains title/metadata, not read authority.
   Thread a separate capability through composition so the resource resolver
   reads bounded relative image references through
   `LocalResourceAccess.DirectoryLease` and `ContainedResourceReader`, with
   the same MIME, count and byte budgets. A missing, changed or inaccessible
   directory follows the existing unresolved-resource policy: warning for
   ordinary standalone HTML, rejection for self-contained HTML/PDF. A file
   open alone does not grant its parent; do not reuse the preview-only
   “Allow preview resources” choice or request broader folder access here.
   Retain the admitted capability through a later Save As rather than
   recomputing the root from the live window.
4. Carry an Export lifetime lease through ordinary HTML and PDF output.
   A different document ID or recovery epoch **before** the freeze cancels.
   After the freeze, Export does not reread live identity: Save As changes
   both ID and recovery epoch in `FileDocument`, but the already admitted
   source/root and selected destination still belong to this operation.
   The export may finish from those frozen values after Save As or a focus
   change. Origin-window close, explicit cancellation or task cancellation
   revokes publication; it never retargets the replacement document. The
   disabled validated operation's active-identity-change revocation cannot
   be reused unchanged after this freeze: Save As itself mints a new URL,
   document ID and recovery epoch.
   Check cancellation during work and use the lease at each final primary
   promotion cutoff. Preserve HTML's companions-before-primary ownership,
   PDF's validated vector/scratch path and both HTML modes. Cancellation is
   not a new multi-file transaction: only owned temporary files may be
   cleaned, previous user output must remain intact, and an unrelated file
   must never be deleted to make a retry pass.

The package interface changes in steps 2–4 are part of this issue's
cross-module architecture. They require independent engineering review before
shipping; no new dependency or owner product choice is implied. A folder
chooser, a new security scope, or a change to #121's preview grant would be a
separate product/security decision.

### Discriminating acceptance

Use controlled suspension at the sheet, contribution parse, resource read,
HTML staging and PDF promotion. Test A/B focus changes, an edit and theme
change before acceptance, and an edit and Save As after freezing. A Save As
before freeze cancels because its new ID/epoch is not the captured origin;
after freeze it must finish from the old pinned source/root and selected
destination, without adopting the new URL. Also test origin close,
cancellation and failure alerts. Assert that HTML and PDF
consume identical frozen source, generation, options and origin, that B never
receives A's sheet or output, and that no primary file appears after revocation.
Package tests cover block directives on/off, absent and swapped directory
capabilities, symlinks, budget/MIME policy, prior-output preservation and
late HTML/PDF cancellation. Then run locked package/app CI and a Release-build
two-window native check. Signed sandbox resource access remains a separate
release acceptance item; source tests alone do not close #117 or #115.
