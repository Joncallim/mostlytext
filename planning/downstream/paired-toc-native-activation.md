# Activate shared table-of-contents navigation in Preview and Export

## Owner summary and current baseline

A TOC entry must reach the same original Markdown heading in native Preview and
exported HTML, preserving source, file safety, focus and Preview-only layout.
Main `6667bc9c` includes qualified PR93 through PR97. This branch started from
PR97 source `45847244` and now includes its verified main merge. PR96/97 full
functional CI, exact actual-product/native receipts and merge trees are verified. Read the binding issue-117-handoff,
EPIC_STANDARD, RELEASE_HARDENING and the preceding source-index/publication plans.
No owner-account native execution, signing or separate-account gate is lifted.

## Resolved ownership and interfaces

MarkdownEngine remains the sole heading allocator and source-index owner.
ExportService owns source-bound HeadingAnchorPreparation and one physical heading
analysis worker, with at most one newest pending request. No extra parser or
third-party dependency is introduced in the app or Preview. All cmark/DOM work
stays off MainActor. Cancelled/superseded callers settle without freeing the
physical slot until computation actually returns. The host invalidates source
presentation synchronously on edits, closure, parse replacement and disappearance.

Carry the read-only preparation, rather than its index alone, into requested
heading Export. The index alone omits the exact authored-ID/name inventory needed
to choose a diagram namespace without redoing raw-HTML analysis. Update the new,
unreleased opt-in ExportRequest interface accordingly; retain no ambiguous trusted
flag or unverified caller-authored reservation list. The same one frozen parse
and preparation drive TOC serialization and Export; the original frozen parser
continues into composition, avoiding a duplicate MarkdownEngine parse.

Keep ordinary no-TOC Export unchanged. When a real top-level marker is present,
prepare its shared index, register linked TOC output and retain the preparation on
the request. If preparation fails, requested Export throws the specific navigation
error before writing any primary/companion. Preview instead preserves the marker
and records a diagnostic; no unverified index/action is published. Empty inventories
retain the readable no-headings placeholder. Marker admission remains semantic,
top-level-paragraph-only; do not turn code, front matter or raw HTML into markers.

## SVG namespace and static target policy

Generated heading fragments contain no uppercase ASCII. Reserve an uppercase
ASCII diagram family MTTOC-SVG- plus the first available canonical decimal counter
and hyphen. Compute occupied counters in one pass over the exact decoded authored
IDs/names, using UTF-8 prefix checks; choose among `0...inventory.count`. Bound numeric
parsing, do not grow a prefix proportionally to a hostile ID or scan the complete
inventory once per candidate. The resulting family is disjoint from all authored
reservations and generated heading IDs. Existing SVG IDs admitted by the disabled
namespace parser are ASCII-only; preserve that supported grammar and its existing
safe source fallback rather than silently broadening its Unicode/CSS rules.

Namespace each accepted occurrence before heading target validation, rewriting all
existing ID/href/CSS/ARIA/font/keyframe references together. Canonical cached art
remains immutable. Do not route ordinary exports through strict/no-script
exportValidatedSVG. Preserve the ordinary authored-HTML policy. Generated roots
must have unique final IDs and internal references; verify the actual assembled
output under its normal template, including authored names. Unknown or unsupported
diagram markup preserves its fence with diagnostics. A requested TOC cannot claim
ambiguous targets. The final target patch remains before URL-slot resolution.
Pure Markdown/ordinary image and simple math fragments keep the structural direct
path; opaque/raw markup retains feature-local DOM bounds, not a new global cap.

## Native authority, links and queued scroll

Generalize the already-qualified math source-binding names internally, with
compatibility aliases preserving existing callers/tests. Reuse all exact
model/editor/published UTF-8, document/recovery/generation, parser identity/revision,
registered-window, key-window and sheet guards. A new heading session publishes
only its current request result. Its live provider never creates an editor/parser
to make a stale request appear current. Preview composition and resolver/index
publication share the same binding ID and exact displayed revision/blocks.

PreviewLinkResolver returns a typed verified-heading or unresolved-internal action
before existing external handling. Bare fragments and complete same-current-file
identity may be internal; a changed query, other file, malformed percent encoding,
controls or unsafe scheme cannot borrow heading authority. Decode fragments once,
compare target UTF-8 bytes exactly, and never send unresolved internal links to
NSWorkspace. Preserve the existing permitted external/web/mail/text-document and
Finder reveal policies. Native callbacks capture the binding ID that rendered the
link, then revalidate the live session/record at execution.

A real link press scrolls Preview to the indexed original heading line. If the
editor is already attached, reset its complete EditorSelectionSet to one heading
range and reveal it; preserve focus. Never mount an editor or change Preview-only
layout for a TOC action. Respect Reduce Motion. Queue the Preview jump with a weak
live-host validation closure and revalidate again at consumption, before computing
and applying the current displayed block target. Stale/wrong-window/closed-host
requests cannot scroll. Rendering itself never changes selection.

## Verification and completion

Before paired production registration, require discriminating namespace, exact
URL/fragment, worker-bound and actual source-binding controls. Compile all real
package/app/UI targets locally; execute native tests hosted only. The real app-shell
probe initializes its own AXApplication and presses actual native link handlers,
including repeated/Unicode headings, raw-only IDs, stale/replaced parsers, secondary
carets, focus, other windows, sheet/closed origin, Preview-only and queued-scroll
staleness. Keep all positive controls and deadlines. Run full locked CI, format,
strict lint, compliance and Release phase measurements. Reconcile current docs and
both #10 rows only to actual demonstrated behavior. Browser/PDF/VoiceOver/exact
signed-artifact and owner-observed acceptance remain explicit release gates.

Stop/reassess if existing template/renderer assumptions fail, ordinary authored
HTML or no-TOC admission changes, linked targets are wrong, work becomes unbounded,
new dependencies are needed, or tests/ceilings would need weakening. This is paired
activation work, not permission to stop after another helper or queued test.


## Composition failure refinement before activation

Source review finds that final heading verification alone does not prove the
requested TOC survived contribution admission, overlap/budget rejection or leaked-
sentinel retry. Carry requiresHeadingNavigation as feature intent on the known
TOC contribution. This flag only tightens failure behavior; it never selects the
structural fast path or grants source/resource authority. The actual composer
records accepted required-TOC source ranges, requires one unique accepted range
per requested TOC after retries, and refuses a required TOC without its read-only
preparation. An ordinary overlapping contribution cannot satisfy that record.
Preview suppresses its heading resolver if TOC composition reports an error.
Tests exercise stale/empty/overlapping/duplicate placements and absent preparation.

Source planning confirms generated TOC blocks deliberately have no authored-source
anchor. The qualified math planner skips those generated blocks, and Preview uses
its non-math Markdown parser for them; escaped labels do not acquire a second
currency/math pass. Preserve this boundary and verify real links in the whole app.

D2's existing SVG namespace corpus deliberately rejects a real fixture with
unresolved paint references. This remains a known compatibility/fidelity question
before final activation acceptance: never call a source-fallback D2 export normal
vector parity. The strict/no-script export route stays disabled. Keep this explicit
while qualifying the native source/action path and resolve the ordinary-route
namespace policy with real renderer/browser evidence before declaring E14 residuals
or the complete release gate finished.

## Ordinary SVG reference compatibility decision

The normal D2 renderer intentionally emits some local paint references without
matching definitions. Renaming an absent local target to an equally absent target
inside a private occurrence family preserves that behavior; inventing definitions
or deleting stylesheet rules would change it. The ordinary heading route will
therefore permit only these syntactically valid, already-local references and
rename them with the same complete SVG/CSS parser. The existing strict rewrite
and disabled validated-SVG operation continue to require every target to exist.
No CSS grammar, resource URL policy or sanitizer rule is broadened.

The ordinary rewrite returns an internal immutable record of each rewritten root,
its declared IDs and all local URL/href/ARIA targets. It does not trust caller
supplied missing-target lists. The source-owned fresh family selects the route.
Final emitted-HTML inspection must find every recorded root exactly once, with
exactly its expected IDs and references, no duplicate IDs or family-valued named
anchors, and no IDs from that family outside the recorded roots. In particular,
a previously absent target must remain absent throughout the complete body;
opaque contributions and HTML parser repair cannot materialize it. Existing
source/retry identity and final target checks still apply. Ordinary authored CSS
and scripts retain their documented policy; this static target proof does not
claim strict dynamic paint isolation from arbitrary authored script/style.

Require default-strict negative controls, missing-target and opaque outside-alias
controls, repeated/mixed real Graphviz/D2/Mermaid output, unchanged canvas pixels,
normal template target identity and zero extra resource requests. Keep the first
hosted native candidate separate from this policy change so runtime failures can
be classified against exact source.


## First hosted native fixture findings

At source `c08f0ed1`, all 27 selected test functions in eight suites executed. Production Export,
heading-session and all four existing math suites pass. The real Preview exposes
AXLink with the correct unique label, but SwiftUI supplies no AXURL attribute;
the initial test lookup wrongly required that attribute and timed out with the
actual links present in its retained accessibility dump. Use the unique native
link role/label, press its actual handler and keep exact original-source selection,
real scroll, focus and Preview-only assertions. URL/fragment policy remains covered
by actual-product resolver tests. This is a lookup correction, not URL publication
or a replacement direct callback.

The direct navigation fixture removes its SwiftUI editor, installs a manual
NSScrollView and then awaits parsing/heading work. Old representable dismantling
can settle across those awaits. Re-establish that fixture's already-real editor
attachment after awaits, require window identity and active attachment before the
positive control, and retain a diagnostic of its prior attachment state. The whole
app-shell positive controls still exercise unmodified production mounts. The
first failed selection is retained and needs confirmation from the new runtime
attachment diagnostic and actual native app tests; it is not silently classified
as a product pass. All five-second deadlines remain unchanged.


## Debug and optimized qualification

Execute the exact actual-product heading tests and the eight app math/heading
suites in separate Debug and Release jobs, retaining each configuration's logs
and source/pin receipts. Preserve each existing job/test deadline. The production
Export test records three complete command-body exports for a source above 1 MiB
with 4,096 duplicate headings, alongside its actual parser phase. Assert exactly
one parse per export and every heading target count, including the final duplicate.
Record raw samples, configuration and source size; these measurements include
file publication but do not claim save-panel, typing latency or peak memory proof.
This does not settle the broader resource-budget or whole-editor criteria.


The final source review also removes a repeated root-by-element lookup: final SVG
ownership builds one ID-to-element table, then inspects each disjoint root subtree.
Reject a root inventory beyond the remaining 4,096-root allowance before per-root
DOM parsing. Every rewritten root necessarily owns at least one ID, so this is an
early application of the existing final 4,096-ID budget, not a smaller accepted
input policy. Test an over-budget inventory, exhausted remainder and a positive
multi-root fragment. No default strict SVG behavior changes.

## Bounded native client after the second interaction stall

The c916 native interaction step did not complete after more than six minutes;
it was explicitly cancelled and is not a pass. Preserve its final output. The
in-process NSAccessibilityProtocol press has no messaging timeout and can block
the test's main actor, preventing the five-second presentation deadline from
running. The exact stalled frame requires a captured stack; do not infer it from
the last logged test alone.

Use the real macOS AXUIElement client from a detached task instead. Search only
this test process's focused window, require a unique native link role and exact
label, set a finite messaging timeout, and bound traversal by time, depth and
node count. Perform kAXPressAction through that client while the app main actor
is free to handle it. There is no direct coordinator/callback fallback. Keep every
source-selection, real Preview scroll, focus, layout and source-preservation
assertion. Split-view focus is deliberately the already-mounted source editor;
Preview-only focus must remain outside its detached editor.

The hosted native execution wrapper will record only the exact test app under
its own DerivedData path, capture bounded stack samples if execution stalls,
and impose a ten-minute command-body ceiling below the existing 35-minute job
ceiling. Existing five-second presentation deadlines are unchanged. An owned
stalled process or command termination is a failure with retained diagnostics,
never a synthetic test success. No local native client or product is executed.


The preserved c916 output now supplies the exact exception stack: SwiftUI's
`AppKitAccessibilityLinkRotorBridge.LinkElement` does not implement
`accessibilityPerformAction:` inherited through `NSAccessibilityElement`'s direct
`accessibilityPerformPress`. The Preview-only test's protocol call triggers an
NSInvalidArgumentException, after which the run stops progressing. This classifies
that specific harness failure; it does not explain the older package WebKit hang
or the separate signal-11 failure under #15. The new AX client invokes the OS
accessibility action API instead of that unsupported inherited protocol method.


The c916 complete package run executes 3,701 tests/528 suites and fails one new
fixture: its authored named anchor deliberately needs ordinary standalone HTML,
but the fixture requested self-contained output, which correctly rejects authored
raw HTML. The real Graphviz/D2/Mermaid canvas comparisons complete before that
rejection with no failed pixel assertion. Retain this first failure. Test both
normal-template variants: raw-free self-contained output and ordinary standalone
output retaining the authored alias. Preserve the four vector diagrams, unique
IDs, exact TOC target and no-resource-request assertions in both cases; do not
change the production raw-HTML admission policy to satisfy the fixture.


## Native TOC controls and optimized link ownership

At eaaacddd the bounded AX client finds exactly the intended inline TOC link,
but each real press returns AX error -25200. That generic error alone does not
classify platform support. Preserve the failed controls and deadlines. Present
already-admitted `.custom("toc")` blocks with standard SwiftUI Link rows, using
only the current host-published heading index and the existing OpenURLAction.
The composer already owns this generated block kind; no new caller trust flag,
module dependency or heading allocator is needed. Plain heading labels must not
be parsed again as Markdown/math. Match the existing nearest-shallower hierarchy,
keep large lists lazy, and retain the no-headings placeholder and source fallback.
Keep all binding, source-selection, Preview-scroll, focus and Preview-only tests.
Record supported native actions on lookup failure; no direct callback fallback.

The same candidate fails Release linking for both architectures: app object
MathPreviewDisplayBuilder references SwiftUIMath validated-body metadata and math
metrics symbols, but the generated app links only the containing package product
frameworks. Declare the existing immutable SwiftUIMath product explicitly in the
Xcode project graph, at exactly MacDownKit's existing owner/revision. This adds no
new dependency bytes or parser, does not change the lock, and leaves the
MathRendering adapter responsible for admission. Do not suppress optimization,
testability, architectures or linker diagnostics. Require the actual Release
app/test link and both configuration executions before claiming resolution.

The two normal-template SVG assertions currently aggregate occurrence count,
root IDs, nested SVG IDs and targets into a single Boolean, losing the failing
fact. Preserve the output semantics while collecting individual DOM facts. A
renderer may contain nested SVG containers without IDs: count outermost SVG
occurrences and validate every declared descendant ID rather than requiring an
ID on every nested container. Still require four real vector occurrences,
unique document IDs, one exact heading/TOC target, expected authored alias,
unchanged canvas pixels and no resource requests. Print the actual facts so a
further failure is attributable. This is not permission to accept diagram loss.
