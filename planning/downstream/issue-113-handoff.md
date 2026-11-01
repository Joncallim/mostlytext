# Issue #113 / E23 — Themes, Quick Look and Finder integration

## Owner summary

Complete the Mac-facing experience with coherent light/dark themes, safe custom themes and a useful offline Markdown Quick Look preview. Reuse existing renderers and ExportService. The extension is read-only, smaller than the app and must preserve source fallback when technical rendering fails.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md), [readiness review](READINESS_REVIEW.md) and linked issue hand-offs. E23 begins only after E22; no current E22 plan/source or active design branch is modified here. Refresh the binding epic-23 implementation file from these decisions and exact post-E22 master, not from the original 83a79a4 symbol inventory.

## Current baseline and fixed scope

E22 now has a real gutter/invisibles/status pane, plural selectionSet with secondary-caret state, language profiles and transforms. DocumentEditorSplitView+EditorPane reads line index and source from the SAME text system because mixing it with a stale binding caused a real crash. Theme application must preserve that ownership and use completed APIs rather than reconstructing an editor.

Themes/ThemeController/PreviewTheme and export/render orchestration remain as originally inspected. ThemeController's catalog is immutable and initial slot lookup can accept a wrong-appearance ID; Preview/Export independently derive colors. No Quick Look target is in this master. #117 now explicitly supports existing Theme snapshots before E23, so anchors/export identity need not wait for the palette refactor.

The public name is MostlyText. The owner owns mostlytext.app and mostlytext.dev, not mostlytext.org. These facts are settled; technical bundle/extension/theme/CLI identifiers are separate recorded inputs, not inferred from domain purchase. Consume the latest owner-approved design register from the design lane, preserving actual waivers as waivers, never reviving superseded human-study gates or inventing passed artwork validation. Do not alter #136/#145 or choose a new mark here. Final Mac icon proof and technical identifiers still need their own records.

Non-goals remain: arbitrary CSS/JS/font/path/remote theme execution, marketplace, visual theme editor, generic Quick Look takeover, new Markdown/diagram syntax, iPad, editor replacement or a marketing-site build. E23 is the last planned capability epic.

## Dependencies without umbrella-issue cycles

E22 completion supplies editor/settings/encoding contracts. E23 palette work is independent of full #117/#118 closure. Tested #117 anchors/destination values and #116 math adapter feed shared presentation. Tested #121 reader feeds consumers where an actual grant exists. #118 supplies checked assembly/policies, while its final GUI evidence may run later. #79 is an E23-owned renderer unit, not a competing theme owner. #88 supplies test infrastructure, but does not require E23 closed before its harness is implemented.

Ready means the named prerequisites for a UNIT are satisfied, not that every whole issue is closed. See the acyclic unit graph in readiness.json. Final acceptance/evidence can remain pending without duplicating implementation. Any missing identity or empirical platform prerequisite blocks only its dependent integration/packaging unit.

## Semantic palette

Themes owns one immutable ResolvedPresentationPalette from a value Theme. Roles: editor/document background and foreground; caret; selection background/foreground; current line; gutter/status foreground/background; invisibles/secondary carets; headings/links/muted/rules; inline/fenced code; quote foreground/background/border. Resolve optional legacy fields once with deterministic fallback and keep token-style hierarchical lookup. Native PreviewTheme and ExportThemeStylesheet adapt this value, not independently mix colors. Add completed E22 find-match/current-match roles when its actual API is ready; do not mutate in-flight Find work now.

A palette change changes colors/necessary font metrics, not source, generation, dirty state, undo history, selectionSet or parser state. Use existing highlighter chrome/capture application and viewport invalidation. Do not rescan the whole document, recreate the text system or rely on AppKit's collapsed selectedRanges as the entire selection model. Test primary/secondary selections, gutter width, invisibles and current-line non-color cues together.

Bundled set: at least eight deliberately distinct themes, at least four light/four dark, including neutral, warm low-distraction and high-contrast directions. Preserve Tomorrow lineage through explicit compatibility/fallback, not accidental undocumented recoloring. Record original palettes or compatible provenance/licenses. No bundled font binaries. Core bundled foreground/link/code roles target at least 4.5:1, meaningful non-text indicators 3:1, high-contrast body 7:1, calculated over resolved actual backgrounds; these are design checks, not blanket accessibility certification. Preserve non-color cues. Imported poor contrast is warned, not forbidden deliberate use.

#79 defines neutral-light-v1 diagram artwork with opaque canvas and tested defaults, keeping print legibility even in a dark app theme. Do not imply arbitrary author diagram colors are recolored or guaranteed readable. All engines use structured context and context-aware caches; PDF uses print-safe policy. Math remains #116's shared engine/context.

## Versioned custom theme format and identity

External schema v1: schemaVersion, stableID, displayName, appearance, declarative semantic/chrome colors and tokenStyles. No executable/configuration/resource fields. Bound file bytes before decode (initially 64 KiB), nesting (8), entries (512) and custom catalog count (256). Use structural validation for duplicate/unknown keys before Codable; reject unsupported versions, wrong types, malformed UTF-8, nonfinite/out-of-range channels, unsafe IDs/capture names and overlong/empty names. Base canvases must resolve opaque. Unknown future files are retained/reported, not silently rewritten as v1.

Corrected identity policy: the catalog's generated user UUID is stable across export, restart and deliberate reimport/update. Built-in IDs are reserved. Importing an unrelated external stableID never overwrites an existing record automatically. If a recognized custom ID already exists, show Replace or Import Copy; Replace retains ID and requires explicit confirmation plus an unchanged before-digest at commit. Import Copy generates a new ID. Byte-identical reimport is a no-op/selection opportunity, not another duplicate file. External provenance IDs may be metadata but do not become filesystem paths or implicit overwrite authority.

ThemeCatalogStore is actor-confined and returns immutable revisioned snapshots. ThemeController stays MainActor/app-wide, with validated mutable catalog and separate light/dark choices. Enforce slot appearance on startup AND selection. Bundled fallback exists even when every custom file fails; never reach an empty-catalog fatalError.

Managed paths derive from validated IDs under the final Application Support/Theme namespace. Import takes a bounded snapshot of the explicitly selected file, validates it, then exclusive-creates a staged managed file and atomically publishes it. No external URL remains an executable/resource grant. Do not follow store/leaf symlinks or overwrite an externally modified target after a stale dialog. Serialize catalog writes and preference publication; a crash leaves readable old/new bytes and deterministic selection fallback, not a lost custom theme.

One debounced catalog watcher per app—not per window—reloads off-main with revisions. An incomplete external write retains last-known-good content and one diagnostic; a later valid version clears it. A confirmed deletion/corruption of the selected theme falls back to a same-appearance bundled theme without deleting the unreadable original. Reject stale reloads after newer imports/selections. Balance watchers and grants on shutdown. Include custom theme files and selection IDs in #18's authoritative migration state.

## Appearance UI and compatibility

One Appearance pane: independent light/dark pickers, real semantic preview sample, import/duplicate/export/delete/reveal/reset, provenance and validation feedback. Use existing appearance preference ownership; do not add a second mode switch merely because this plan mentions system/light/dark. Avoid a full color-well designer. Duplicate built-ins to editable custom copies; never mutate a built-in via imported ID.

Preview includes prose/headings/link/quote/inline and fenced code, actual token styles, selection and E22 chrome. All controls are keyboard/VoiceOver accessible, resized/pseudo-localized and appropriately cataloged. Theme proper names may remain names; descriptions/errors/actions are localized.

Current EditorSettings now includes required showsStatusBar while synthesized decoding still lacks a missing-field migration. #53/#18's typed settings compatibility unit must preserve older blobs before final migration/first-run writes; do not reset an old editor domain when applying a theme. Do not assign editorShowWordCount from original MacDown to showsStatusBar: their meanings differ.

## Shared presentation and stateless decoding

DocumentPresentation owns only immutable orchestration: source -> one MarkdownEngine parse/index -> first-party contributions -> existing ExportService composition -> prepared static result. Dependencies may point to MarkdownEngine, Contributions, existing renderer value modules and ExportService. ExportService must NOT depend back on DocumentPresentation. Platform rendering is injected through existing adapters. No WindowCoordinator/Workspace/QuickLookUI/settings UI in this package.

PresentationRequest includes original source/identity, effective parse policy, semantic palette, destination policy, explicit ResourceGrant, trusted limits and deadline. PreparedPresentation contains final immutable bytes, approved attachment bytes, diagnostics and verified anchors. Normal Export adopts the same orchestration after its regression lock. Quick Look is a distinct passive composition policy, not a fake PDF destination URL.

Expose a narrow stateless FileCore decoder taking bounded bytes and returning text plus encoding metadata, through the final E22 encoding policy. It must not instantiate FileDocument, RecoveryBuffer, session writers or filesystem observers. A Quick Look request cannot know an editor's per-document manual encoding override unless explicitly persisted/granted; do not invent heuristics or read app sessions. Safe automatic decoding remains strict; unsupported ambiguous bytes return a controlled readable-error fallback rather than lossy conversion. No source write or implicit newline/BOM normalization.

## Data-based Quick Look provider

Use QLPreviewProvider with explicit QLPreviewingController conformance and the actual shipping SDK's providePreview callback/async declaration. The 1 November 2026 macOS 26.5 SDK check below corrects the earlier instruction against that conformance: it is required by the actual SDK and Apple's provider documentation. A data-based provider is not a view-controller clone; do not invent a cancellation callback. QLPreviewReply's data factory is synchronous: the selected design completes rendering/attachments FIRST, then lets the factory return frozen Data only. It must not start asynchronous render work, mutate caches or read files each time the system asks for bytes. Fill matching attachments/stringEncoding/title before handing off the reply. A repeated factory call returns identical bytes without restarting work.

This precomputed-payload design is a project choice, NOT an Apple API requirement. Apple's Objective-C initializer documentation recommends doing heavy work inside dataCreationBlock so Quick Look can present loading UI early. QL-REPLY must therefore measure the proposed provider-callback/preparation timing against that documented lifecycle, including cold launch and slow rendering. Do not treat a synchronous factory signature as proof that precomputing before the reply is the best execution placement. Retain the selected design only if its actual callback timing, fallback delivery and responsiveness pass; otherwise record a narrow execution-placement revision before broad integration. Do not bridge async work by blocking MainActor or the executor required by that work.

Add target/resources/Markdown UTIs/entitlements in project.yml and regenerate. Register only intended Markdown, not public.text/data/HTML/JSON/source-code. No App Group merely to share theme preferences. Bundle one system-adaptive light/dark reader pair from semantic palettes. A cold Finder preview must work without the app ever launching.

A requested file grants only the actual capability supplied. Read that file with bounded descriptor-backed admission and use ResourceGrant.singleFile/none for authored resources unless a genuine wider grant exists. Parent URLs do not create directory permission. Inaccessible local images become alt/source placeholders. Generated math/diagram output is in-memory cid attachments. Never accept authored cid/data strings as references to internal attachments without a registered admission record.

Escape/suppress authored raw HTML in Quick Look's passive serializer before it enters output. No authored script, style/event handler, remote resource/font, frame/object/embed/form or active SVG. Use restrictive generated CSP and registered cid references; no filesystem baseURL. Keep deliberate safe links separate from automatic loads. Use passive raster attachments for technical output where SVG/foreignObject safety cannot be demonstrated by the existing renderer's supported path; preserve real vector output for ordinary HTML/PDF. Do not add a third renderer. Internal first-party WebKit engine execution stays in its existing isolated harness; D2's internal WASM exception never leaks into returned HTML.

## QL-REPLY probe and request lifecycle

First Quick Look unit: compile the actual macOS 26 data-provider/attachment APIs, install a minimal signed/ad-hoc extension and return one static HTML+cid image. Record file permissions actually granted, callback executor expectations, system cancellation behavior and repeated data-factory calls. Exercise failure/completion once and cold Finder invocation. Prove that the chosen reply-control executor can deliver a prepared fallback while a renderer is slow; do not infer that from async syntax. Include the initializer's documented loading/factory lifecycle and retained-payload tests below.

Only after that passes integrate shared rendering. Every request has its own immutable context and terminal gate: admitted -> reading -> preparing -> deriving -> replied/failed/cancelled. Multiple system requests are independent; 'new request' must not automatically cancel a still-live different request. Late results cannot change an already-delivered reply. Only actual system cancellation/disposal, deadline or that request's own revocation ends its result-production permission. The replied/cancelled state does not itself mean associated workers or captured payloads have been freed.

Prepare safe source fallback BEFORE starting optional expensive derivations. Initially cap rich source at 8 MiB; over-limit files get a clearly labelled bounded prefix preview (at most 64 KiB using encoding-safe boundary handling), not a whole-file parse followed by truncation. Initially cap final HTML+attachments at 16 MiB, individual attachments at 4 MiB, count at 64 and raster pixels at 16 million. Final actual caps follow documented Release calibration, never an unmeasured PASS. All byte reservations occur before worker admission, and actual serialized output is checked.

Use one absolute approximately two-second optional-derivation deadline, not two seconds per equation/diagram. A controller can revoke result publication and return its already-prepared fallback without awaiting an uncooperative child. Retain the worker slot/resources until it ACTUALLY drains. A timed-out WebKit worker is quarantined; do not spawn unlimited replacements. If a required API blocks the reply executor so the fallback cannot return, the QL-REPLY probe fails and that integration requires a narrow execution-boundary revision. TaskGroup cancellation or a MainActor sleep timer is not a hard deadline for synchronous typesetting/WASM. Do not claim stopLoading instantly interrupts them.

### Delivered reply and payload retention

Apply #121's separation of consumer permission, worker occupancy and retained app-owned bytes. The final reply closure captures a minimal immutable payload holder and its reservation, not the provider, original request, renderer, file lease or QLPreviewReply itself. Use the closure's reply parameter rather than capturing the reply into its own escaping closure. This prevents a reply/closure retain cycle and permits source descriptors and renderer state to retire independently after their real work drains.

Returning a reply hands it to the framework; it is not proof that its data/attachments or escaping factory have been released. Keep the provider-owned payload reservation charged while our captured backing holder remains retained, and release through an exact-once lease owner independent of the completed request task. A cache must retain the same lease or transfer its charge; making another physical copy requires capacity. Framework-internal copies/decoded images are measured separately, not claimed bounded by our ARC observations.

In addition to per-reply limits, initially bound provider-owned active/retained reply payloads to 64 MiB total and eight reply holders per extension process, with a bounded admission queue. These are defensive starting caps requiring the existing Release calibration. Reserve capacity for the fallback before admitting optional derivation. If even minimal fallback admission is exhausted, return one controlled resource-exhaustion error rather than create unlimited fallback payloads. Do not reclaim a still-retained reply's capacity by timeout or silently invalidate data the system has been promised. Deadlines may stop production but do not falsify physical resource accounting.

Tests retain several replies after provider completion, invoke factories more than once, cancel other requests, drop references in different orders and simulate a late renderer result. Assert stable bytes, no re-render, no provider/request/renderer retain cycle, no premature refund and bounded subsequent admission. Verify real lifecycle behavior in QL-REPLY rather than assume when Quick Look releases its objects.

One failed/over-budget math, diagram or TOC becomes that contribution's readable source with diagnostics; normal valid within-budget fixtures must still render. #117's anchor failure must never blank the document. Core Markdown rendering failures are one controlled fallback/error, with no duplicate completion. Byte caps do not prove total WebKit decoded-memory bounds; measure worker/process behavior separately.

## Finder and final identity

Consume the latest approved technical identity record for app/Quick Look IDs, theme UTI/extension, public CLI, defaults/support/recovery migration and public update URLs. MostlyText/domain ownership is already settled; missing technical IDs or deployment are not permission to guess. Reuse approved design assets from their owning lane, and preserve recorded waivers rather than falsely passing rejected tests.

Correct Markdown handler rank to the deliberately verified Editor role rather than claiming ownership of the public format. Keep intended import/type declarations and normal dedupe/open lifecycle. Do not programmatically seize default applications or broad text preview ownership. Verify clean-install Open With, extension discovery/enabling and side-by-side legacy installation.

Final production artwork must populate required slots, compile with actool and be checked in Finder/Dock/Launchpad/small-size/system appearance presentations. A generated placeholder or filled catalog is not final approval. Do not create/change brand art within this implementation architecture.

## Units and completion evidence

A. Post-E22 interface/identity intake and QL-REPLY probe (before full extension integration).
B. Semantic palette and eight bundled themes; integrate #79's context/cache/print policy and calibration.
C. Stable-ID theme catalog/validation, Appearance UI and settings-compatibility integration.
D. DocumentPresentation plus stateless decoder consuming tested #116/#117/#118/#121 units; existing Export tests remain green before Quick Look is added.
E. Static provider, registered attachments, fallback/deadline/control lifecycle and hostile-input corpus.
F. Finder/approved icon integration, genuine Release UI/Quick Look/VoiceOver/performance/security evidence via #88; hand exact results to #115.

Test malformed/duplicate/unknown JSON, future schemas, built-in ID collision, replace/copy/no-op import, interrupted writes, external edits/deletes, wrong-appearance selections, 1 MiB theme switching with multicursor and no parse increase. Quick Look corpus includes empty/front-matter-only/GFM/Unicode/BOM/EOL/non-UTF data; valid and broken math/all three diagrams; raw HTML/script/CSS/SVG/font/URL attempts; unavailable resources; huge files/diagrams; concurrent requests; deadline after partial completion; retained replies/factories; cold starts and 100 cancel/next/previous cycles. Verify actual network denial, current/peak worker counts and retained memory, not only configuration strings or nonblank images.

Run serial format/strict lint, full package/app/extension builds and affected regressions, then real registered Finder previews. Targets remain ordinary Markdown <=1 MiB median <300 ms and p95 <750 ms on a named M-series machine, and representative technical content around a two-second total derivation budget. Report cold/warm results and fallbacks; do not loosen requirements merely to label all diagrams successful.

Second review corrected stale E22 assumptions, catalog ID churn, settings-reset risk, cyclic orchestration, invented provider conformance/cancellation, synchronous data-factory misuse, per-request identity, precomputed fallback and false deadline claims. Continuation review distinguishes our precomputation choice from Apple's recommendation and bounds retained replies without equating callback completion with deallocation. Architecture choices are fixed subject to their named feasibility gates; QL-REPLY, calibration, final artwork/identity and real evidence remain explicit prerequisites. E23 closes only with its actual full acceptance and E23-owned #79/#115 evidence, not package tests alone.

Primary API references inspected in the continuation review: https://developer.apple.com/documentation/quicklookui/qlpreviewreply/init(dataofcontenttype:contentsize:createdatausing:) and https://developer.apple.com/documentation/quicklookui/qlpreviewreply/initwithdataofcontenttype:contentsize:datacreationblock: .

## 2026-11-01 shipping-SDK reconciliation

The [compile-only API control](evidence/quicklook-api-2026-11-01/README.md)
proves that QLPreviewProvider does not supply an overridable providePreview
method itself. Its subclass explicitly conforms to QLPreviewingController.
The async protocol implementation and reply/attachment APIs compile in Swift 6
with complete strict concurrency and warnings as errors. stringEncoding takes
String.Encoding (`.utf8`), not its UInt rawValue. This is a narrow correction to
the provider declaration, not authorization to bypass QL-REPLY. No extension
was packaged, registered or invoked by this control. The precomputation versus
data-factory lifecycle and all real Finder evidence remain unproven.
