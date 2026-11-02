# Epic 12 Implementation Architecture — HTML/PDF Export

> **Status:** Binding implementation contract for `epic/12-export`
> **Epic:** #13 — `[EPIC-12] Export: HTML + PDF, templates, themes and derived-content contract`
> **Baseline:** `master` at `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`
> **Architecture date:** 2026-08-17
> **Review status:** Final adversarial pass complete; implementation begins with Slice 0 only

## 2026-11-02 ordinary publication amendment

Ordinary HTML now uses the descriptor-relative writer shared with the optional
validated path. A parent-device/inode gate serializes publication after assembly.
The selected parent must already exist; no intermediate paths are created by the
writer. Sidecars require a v2 marker bound to the exact primary leaf; unknown and
legacy directories, symlinked directories/primaries/resources, changed identities
and same-stem owner collisions are refused without adopting or deleting files.
Existing resources are reused only after bounded no-follow byte comparison.

All retained flat entries count toward a provisional 513-file/128-MiB ceiling,
including the marker and unknown user entries. Old assets are kept; growth stops
at the ceiling. Ambiguous scratch residue blocks another allocation. Primary
scratch names bind to the leaf digest. Normal/cancelled staging cleanup moves a
name to exclusive quarantine before verifying the original inode and bytes;
mismatches restore without replacing an occupied path or report a recovery URL.
No filename-pattern deletion or automatic legacy adoption is performed.

Ordinary origins now use the existing lifetime revocation hooks. Their lease
flows through preparation to the HTML/PDF publication cutoff; text edits keep
the captured snapshot, while window/document identity changes revoke it. Native
close/print timing is still unverified. Observed primary baselines are rechecked,
and absent primaries promote without replacement. Existing-file precheck plus
rename is not a filesystem compare-and-swap. Authorization-time parent/target
admission, inventory-backed transaction journals/automatic crash repair, fully
proved external-writer/root-membership exclusion and native/exact-artifact
acceptance remain #118/#183 gates. The optional SVG path remains disabled.

Publication review also completed fallback-title namespace exclusion and CDATA
context rejection for resource slots. Neither change enables another renderer.

## 2026-11-02 generated resource substitution amendment

The composer now registers unique image-URL occurrence tokens only for resolved,
emitted cmark image nodes. A quote-aware UTF-8 scanner consumes each private token
exactly once in an img/src attribute, restores its encoded companion URL, and
records the precise byte range and admitted identity. The private slot table is
bound to the completed body digest; final assembly validates that binding and
embeds only those ranges. Code/prose, navigation links and authored raw HTML are
never inferred to be generated references from their filenames. The opaque
namespace is excluded from source, destination, stylesheet and derived inputs,
and unresolved/misplaced/duplicate tokens reject the render. Images and links
inside image descriptions do not emit URL attributes and register no occurrence.

The public prepared-document initializer grants no substitution authority;
self-contained assembly of a manifest-bearing manual value fails without the
private registry receipt. Companion assembly preserves manually supplied body
bytes. Both paths reject a stale attached receipt. Source resolver grants/TOCTOU
remain unchanged and open. See export-resource-slots-and-publication.md for the
bounded publication unit and remaining #118/#183 gates.

## 2026-11-02 final HTML assembly amendment

`ExportHTMLWriter.selfContainedHTML` and `companionHTML` now throw on final
assembly failure. `ExportResourceBudget.maxFinalHTMLUTF8Bytes` owns a 256 MiB
provisional ceiling for the complete document. `BoundedExportHTML` first counts
the exact UTF-8 shell, scalar-escaped metadata, CSS/head, body and every embedded
resource occurrence without materializing final HTML or base64. Only an admitted
document is rendered, with checked appends and cancellation. Directory reference
forms are scanned with cached next matches; used resource encodings are shared
within that render. Ordinary HTML completes this gate before destination/sidecar
mutation; the PDF adapter propagates failure before creating/loading WebKit.

This supersedes earlier prepared-body-only sizing descriptions. It does not
freeze measured Release memory limits or establish PDF responsiveness. Textual
resource replacement remains collision-prone until registered URL slots land;
explicit input resource leases, output authority/recovery and stale managed
assets remain #118 work. The optional validated-SVG path remains disabled.
Implementation and source-control evidence are recorded in
`planning/downstream/mostlytext-packaging-and-export-bounds.md`; native and
exact-artifact gates remain separate.

## 2026-09-21 as-built reconciliation

> **Authority amendment:** E12 shipped successfully, but several symbol/type sketches below describe the pre-implementation design rather than the final code. For implementation truth, the as-built mapping in this section supersedes conflicting symbol names/shapes below. The product/security/file-safety invariants remain binding.

The shipped architecture retained the intended one-composer/one-export-destination design but simplified several planned abstractions:

| Planned architecture name/shape | Shipped owner / implementation |
|---|---|
| `ExportSourceSnapshot` nested inside a target-bearing `ExportRequest` | `ExportRequest.swift`: flat immutable `text`, `sourceGeneration`, `theme`, `documentURL`, `contributions`; the destination remains an argument to `ExportService.prepare/exportHTML` rather than stored in the request. |
| `CMarkHTMLBodyRenderer` | `CMarkGFM.swift` plus `ExportComposer.renderBody`: the cmark-gfm bridge and composition policy are split by responsibility rather than wrapped in the planned protocol/type. |
| planned `DerivedCMarkInjector`/derived AST injector | `DerivedContentComposer.swift` + `InlineSentinelIndex.swift` + `CMarkGFM.CustomNodeSpec`: renderer-neutral contributions are validated/spliced through deterministic sentinels and restored as custom nodes. |
| planned mutable resource/manifest builder shapes | `ExportResourceResolver.swift`, `ExportManifest.swift`, `ExportResourceBudget.swift`, `ExportHTMLWriter.swift` and `ExportFileWriter.swift`: resolution, budget and publication responsibilities are narrower than the sketch below. |
| planned Theme→CSS mapper / structural sheet | `ExportThemeStylesheet.swift` + bundled `Resources/structural.css`; E23 may further centralise semantic colour derivation, but Export does not own a second theme model. |
| planned app-side `WebKitPDFRenderer`/page-layout naming | `MacDown2/PDFExportAdapter.swift`: real `WKWebView` → `NSPrintOperation` → PDF pipeline consuming the same `PreparedExportDocument`. |
| future contribution adaptation described generically | `MacDown2/ExportContributionAdapter.swift` and the export-only contribution registry assembly in `MathExportRegistry.swift` / renderer registry files; E23 may extract this orchestration into a shared read-only presentation seam for Quick Look. |

Other important as-built facts:

- `ExportService.prepare` still performs a fresh local parse and never consumes Preview's debounced view state.
- Preview/Export technical content still converges on the E12/E14 derived-content contract; later math/diagram epics proved this seam without replacing `ExportComposer`.
- Authored-source preservation on failed/stale/out-of-range/overlapping derived contributions is implemented in `DerivedContentComposer`; failed derived output falls back to authored Markdown with diagnostics.
- Ordinary/self-contained/PDF target policies are implemented in `ExportComposer.Policy`; do not infer policy from the older planned type sketches below.
- PDF pagination now has a genuine non-mocked `PDFExportAdapterTests` torture test, but #115 requires that test to execute successfully on a suitable interactive macOS 26 environment before production 1.0.

When maintaining E12, inspect current source first. The remainder of this document remains useful for design rationale and invariants, but a stale planned symbol is not permission to recreate an obsolete abstraction.

## Owner summary

Epic 12 implements one local/offline Markdown export pipeline. It prepares one complete HTML document, then either writes that document as HTML or prints that **same prepared document** to PDF through an isolated macOS adapter. PDF does not get a second Markdown renderer.

The final pass deliberately removes choices that the product does not need and fixes every implementation decision at one owner:

- the app supplies current editor text, saved file URL if any, `FileDocument.mutationGeneration`, parse options, selected theme, target and renderer-neutral derived results;
- `ExportService` derives resource root, metadata behaviour, output layout, built-in template, cmark configuration and production budgets;
- `swift-cmark` 0.8.0 is the sole Markdown-to-HTML engine in E12 and is hidden behind one adapter;
- cmark GFM extensions are configured **before parser feed/finish**; render policy is configured separately;
- authored raw HTML is preserved for ordinary HTML/PDF with cmark `UNSAFE + tagfilter`, but Markdown link/image nodes receive an explicit centralized dangerous-URL policy because `CMARK_OPT_UNSAFE` also disables cmark's normal dangerous-link scrub;
- themes stay as theme data; E12 maps existing theme tokens to CSS variables and one bundled structural stylesheet;
- resources use one resolver, one transient manifest builder and one immutable final `ExportManifest`;
- durable companion filenames are exactly `<full-sha256>.<canonical-extension>` and resource identity is `(sha256(bytes), canonical media type)` so MIME handling never depends on first-seen order;
- a valid ownership marker makes `report.assets` an E12-managed directory and reserves the content-address filename namespace; files outside that reserved namespace are never touched;
- future E14/E19-E21 output enters through one generic source-range seam supporting **inline and block** placement. E19 inline math therefore does not require redesigning E12;
- derived identity uses the original source's UTF-16 coordinate space plus the source `UInt` generation. cmark source-position metadata is not used as durable identity;
- successful derived source is replaced by deterministic sentinels before cmark parses it, then sentinels become cmark custom inline/block nodes. This prevents future TeX/diagram syntax from being accidentally reparsed as Markdown while preserving the one-renderer rule;
- self-contained HTML is a real closure contract for E12-visible resources: managed CSS/assets are embedded, authored raw HTML is rejected, and unresolved/remote resource-bearing references are rejected;
- PDF uses the same prepared HTML/resources through a manifest-only local URL scheme in locked-down WebKit with JavaScript/network/navigation/download/popups disabled;
- E12 contains no math/Mermaid/Graphviz/D2/WaveDrom branch, no global export singleton and no caller-supplied arbitrary layout/policy object.

This document is the implementation contract required by `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. A worker should not make a new architectural choice where this document already fixes one.

---

## 3.1 Current repository state and dependency reconciliation

### Binding current-master facts

1. `MarkdownEngine.ParseEngine` owns the app's renderer-neutral Markdown/front-matter parse. Export continues to call injected `ParseExecuting`; it does not leak `swift-markdown` types outside `MarkdownEngine`.
2. `MarkdownDocument` already contains `body`, `bodyLineOffset`, original-source `SourceMap`, blocks, front matter, parse revision and the actual `MarkdownParseOptions` used for the parse.
3. `FileDocument.mutationGeneration` is `UInt`. E12 preserves that type at its boundary and exact-converts only at the `ParseExecuting` call, whose current revision parameter is `Int`.
4. `ThemeController`/`Theme` are the theme source of truth. E12 must not add export-theme models or duplicated palettes.
5. E11 demonstrates a local/offline WebKit posture, but Preview owns its implementation. `ExportService -> Preview` is forbidden.
6. `ExportService` already exists in MacDownKit and currently depends on `MarkdownEngine` and `Themes`.
7. The migration plan deliberately selected `swiftlang/swift-cmark` 0.8.x for HTML export. E12 pins exact 0.8.0 and verifies the C surface in Slice 0.
8. E14 owns contribution discovery/lifecycle/isolation; E12 owns only the export destination. E19 explicitly requires inline/display math and E20 block SVG diagrams, so the destination contract must support inline and block source ranges without knowing renderer languages.
9. Open issue #35 still allows non-Markdown formats into the Markdown path. E12 does not absorb that work; export UI is Markdown-only until another format owns an adapter.

### Dependency change

`MacDown2/Packages/MacDownKit/Package.swift` must add:

```swift
.package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.8.0")
```

Only `ExportService` receives the required cmark products (`cmark-gfm`, `cmark-gfm-extensions`). No app/Preview/other package target imports them.

Do not add another Markdown parser, templating engine, HTML parser, PDF library, hashing library or network client for E12. System modules/frameworks are sufficient: `Foundation`, `CryptoKit`, `UniformTypeIdentifiers`, plus app-side `AppKit`, `WebKit` and `PDFKit`.

### Legacy migration rule

No reliable concrete `MPAsset` implementation contract is present in current MacDown 2. Port behaviour, not obsolete class shape:

- logical resource identity;
- bytes + media type;
- deterministic lookup/deduplication;
- embed/bundle behaviour;
- template concepts `title`, `style`, `content`, `assets`;
- explicit default/fallback behaviour.

If a material legacy contract is later found that changes current acceptance behaviour, stop and revise this architecture. Do not recreate a legacy type because of its name alone.

---

## 3.2 Representative user journeys

### A. Self-contained HTML

User exports current dirty Markdown as self-contained HTML. The app snapshots current text/generation, E12 freshly parses it, resolves all E12-visible local resources under the document root, embeds CSS/resources and atomically promotes one HTML file. It opens without MacDown 2 or companion files.

### B. Companion HTML

User exports HTML with companion resources and embedded or linked CSS. E12 writes content-addressed resources into `report.assets`, then atomically replaces `report.html`. A valid E12 marker owns the directory's reserved content-address namespace; arbitrary other files in that directory survive untouched.

### C. PDF

E12 prepares the same HTML as above using local-scheme resource references. App-side locked-down WebKit loads only the prepared document/manifest resources, prints with the macOS print system, validates the temporary PDF with PDFKit and atomically promotes it. Text remains searchable/selectable.

### D. Future inline math

E19 later supplies renderer-neutral output for a source range such as `$E = mc^2$`. E14 maps it to E12 placement `.inline`. E12 substitutes that range with a deterministic sentinel before cmark parsing, then swaps the sentinel for a cmark custom-inline node. No math branch or second renderer is added.

### E. Future diagram block

A Mermaid fenced block follows the same path with `.block`; the custom block replaces only the derived source while list/quote containers remain cmark-owned. SVG/resources enter the ordinary manifest path.

### F. Derived failure/staleness

Failed, stale, overlapping or structurally unusable derived output is not substituted. Its authored Markdown reaches cmark unchanged and the export records a diagnostic. Silent omission is forbidden.

---

## 3.3 Invariants and non-goals

### Invariants

1. **Current text wins:** export snapshots live editor text, not last save or debounced preview output.
2. **Fresh parse:** every request calls `ParseExecuting.parse` on that immutable snapshot.
3. **One Markdown HTML renderer:** cmark-gfm only.
4. **One prepared document:** PDF consumes the same prepared HTML model as HTML export.
5. **No caller-built layout/policy:** request chooses target/options; service derives layout/root/template/metadata/budget policy.
6. **Generation stays `UInt`:** no unrelated public `Int revision` domain.
7. **Original-source coordinates:** derived ranges are half-open UTF-16 offsets into the original snapshot, front matter included.
8. **No cmark source-position identity:** cmark source positions may aid diagnostics only, never stable source identity.
9. **No overlapping rendered ranges:** overlapping successful contributions fall back to source with diagnostics.
10. **Derived failure preserves source.**
11. **No renderer-language branching:** E12 knows source ID/range/generation, inline vs block placement, passive HTML, diagnostics and resources only.
12. **Offline first-party operation:** no export fetch/upload.
13. **Self-contained means closed:** every E12-visible rendering resource is embedded; authored raw HTML is rejected.
14. **Path containment:** relative local resources may read only regular files canonically inside the saved Markdown file's parent directory.
15. **Unsaved means no implicit resource root:** E12 never guesses the process working directory.
16. **Typed content address:** final resource key is full SHA-256 bytes digest + canonical media type.
17. **One immutable final resource source:** `PreparedExportDocument` contains one `ExportManifest`, not duplicate resource arrays.
18. **Resources before primary:** new companion HTML is never visible before resources it references exist.
19. **Managed-directory namespace:** an E12 ownership marker is required before E12 may modify `report.assets`; within that managed directory only exact reserved marker/temp/content-address names are app-owned. Other names are never adopted/deleted.
20. **Determinism:** same complete request + same built-in stylesheet/template/config version yields byte-identical prepared HTML and resource names. No timestamps/random UUIDs/process IDs in durable output.
21. **Concurrent windows:** no global export singleton/actor; invocation state is local.
22. **No `@unchecked Sendable` shortcut.**
23. **No source mutation:** export never saves/reformats/edits Markdown.
24. **No hand-edited `.xcodeproj`:** use XcodeGen.

### Non-goals

- production math/diagram rendering;
- custom user template UI/loader;
- ePub/DOCX;
- hosted rendering;
- SwiftUI preview-view export;
- generic third-party plugin host;
- arbitrary HTML crawler/sanitizer;
- issue #35/non-Markdown export;
- custom paper-size/pagination engine.

---

## 3.4 Module ownership and dependency boundaries

### `MarkdownEngine`

Owns Markdown/front-matter parse and original-source map only. No export policy moves into it.

### `Themes`

Owns theme values only. No CSS/template/PDF rules move into it.

### `ExportService`

Owns platform-neutral composition:

- public request/result/derived contracts;
- `UInt -> Int` exact parser conversion;
- cmark parser/extension/render configuration and AST mutation;
- Markdown URL safety policy;
- fixed metadata rules;
- one built-in template;
- one structural stylesheet + Theme→CSS variables;
- source-root/resource containment/snapshot/hash/media type;
- transient manifest builder → immutable manifest;
- destination resource references;
- derived range/sentinel/custom-node adaptation;
- output-layout derivation;
- companion directory ownership/write protocol;
- Foundation-only atomic single-file promotion;
- diagnostics and budgets.

Must not import `AppKit`, `WebKit`, `PDFKit`, `Preview` or E14/E19-E21.

### App target

Owns export command/panel, FileDocument/editor snapshot, ThemeController selection, save panels, per-window task/progress/cancel, localised presentation, `WebKitPDFRenderer`, `PDFPageLayout`, scheme handler, PDFKit validation and composition-root wiring.

### Future contribution modules

E14/E19-E21 own recognition/rendering/cache/lifecycle and adapt their renderer-neutral results into E12 types. They do not own a parallel document exporter.

### Forbidden dependency directions

- `ExportService -> Preview`
- `ExportService -> FileCore` (not needed; app maps current values)
- `ExportService -> E14/E19/E20/E21`
- `Themes -> ExportService`
- `MarkdownEngine -> ExportService`
- app/Preview direct cmark imports

---

## 3.5 Interfaces and data contracts

The names may receive normal Swift-style adjustments, but shape/ownership/invalid-state guarantees are binding.

### Request

```swift
public struct ExportSourceSnapshot: Sendable {
    public let text: String
    public let fileURL: URL?
    public let parseOptions: MarkdownParseOptions
    public let generation: UInt
}

public enum ExportTarget: Sendable, Equatable {
    case html(url: URL, options: HTMLExportOptions)
    case pdf(url: URL)
}

public struct HTMLExportOptions: Sendable, Equatable {
    public let packaging: HTMLPackagingMode

    public static let standard = HTMLExportOptions(
        packaging: .companionFiles(stylesheet: .embedded)
    )
}

public enum HTMLPackagingMode: Sendable, Equatable {
    case selfContained
    case companionFiles(stylesheet: ExportStylesheetMode)
}

public enum ExportStylesheetMode: Sendable, Equatable {
    case embedded
    case linked
}

public struct ExportRequest: Sendable {
    public let source: ExportSourceSnapshot
    public let target: ExportTarget
    public let theme: Theme
    public let derived: [DerivedExportResolution]
}
```

Request deliberately has no `resourceRootURL`, `suggestedTitle`, `Int revision`, metadata policy, resource budget, output layout or template ID. Those are service-owned or derived; callers cannot construct contradictory combinations.

### Derived destination

```swift
public struct DerivedSourceID: Hashable, Sendable {
    public let rawValue: String
}

public struct ExportSourceRange: Hashable, Sendable {
    public let lowerUTF16Offset: Int
    public let upperUTF16Offset: Int   // half-open
}

public enum DerivedExportPlacement: Sendable, Equatable {
    case inline
    case block
}

public struct DerivedExportAnchor: Hashable, Sendable {
    public let sourceID: DerivedSourceID
    public let range: ExportSourceRange
    public let placement: DerivedExportPlacement
    public let generation: UInt
}

public struct DerivedExportResource: Sendable {
    public let id: String
    public let mediaType: String
    public let data: Data
}

public struct DerivedExportFragment: Sendable {
    public let html: String
    public let resources: [DerivedExportResource]
}

public enum DerivedExportResolution: Sendable {
    case rendered(anchor: DerivedExportAnchor, fragment: DerivedExportFragment)
    case failed(anchor: DerivedExportAnchor, diagnostic: ExportDiagnostic)
}
```

`ExportSourceRange` constructor rejects negative, empty/inverted and overflowing ranges. `ExportService` additionally checks current-source bounds and that both UTF-16 offsets map to valid `String.Index` boundaries.

`DerivedSourceID` is opaque; never parse renderer/language information from it.

`DerivedExportFragment.html` is trusted **first-party destination HTML**, not user/third-party plugin HTML. E14 later owns first-party admission. It must be passive/offline and must not require scripts/network or contain complete `<html>`, `<head>`, `<body>` or `<base>` wrappers.

Derived resources may be referenced only through `DerivedExportResourceReference.reference(for:)`. That helper owns the one internal logical reference literal. Before a custom cmark node is created E12 rewrites every declared logical reference to the destination-managed reference. Duplicate IDs, unresolved canonical prefixes or budget violations reject that contribution and preserve source.

For self-contained closure, the first-party derived contract additionally requires that resource-bearing attributes inside `html` use only those declared canonical references; E14/E19-E21 adapter tests must enforce that producer contract. E12 does not add an HTML parser solely to distrust its own first-party adapter.

### Sentinel/custom-node algorithm

For all statically valid `.rendered` candidates:

1. Sort deterministically by `(range.lower, range.upper, sourceID.rawValue)`.
2. Reject stale generation, front-matter ranges, invalid UTF-16 boundaries, duplicate identity/range and overlapping rendered ranges; rejected source remains untouched.
3. Build deterministic ASCII sentinel from `sourceID + range + generation` using SHA-256. If source already contains it, append the smallest deterministic numeric suffix not already present.
4. Map absolute source UTF-16 offsets to `MarkdownDocument.body` offsets using `bodyLineOffset` + `SourceMap`.
5. Substitute accepted ranges from highest offset to lowest.
6. cmark parses that transformed body.
7. Locate each sentinel exactly once.
8. `.inline`: it must occur in replaceable inline literal text; split text node around sentinel and insert `CMARK_NODE_CUSTOM_INLINE` with rewritten fragment as `on_enter`, empty `on_exit`.
9. `.block`: choose nearest replaceable block whose semantic content is only that sentinel; replace it with `CMARK_NODE_CUSTOM_BLOCK`, preserving outer list/quote/container nodes.
10. If a candidate fails structural injection, remove those failed candidates and reparse once so their authored source returns.
11. If that second pass is structurally unstable, perform one final parse with **no derived substitutions** and emit diagnostics for all derived candidates. No unbounded reparse loop.

This design intentionally removes successful inline technical syntax before cmark can interpret its characters as Markdown while retaining cmark as the sole Markdown renderer.

### cmark adapter

```swift
protocol MarkdownHTMLBodyRendering: Sendable {
    func render(
        document: MarkdownDocument,
        originalSource: String,
        derived: [DerivedExportResolution],
        resolutionContext: ExportResourceResolutionContext,
        referenceMode: ExportResourceReferenceMode,
        budget: ExportResourceBudget
    ) async throws -> RenderedHTMLBody
}

struct RenderedHTMLBody: Sendable {
    let html: String
    let resources: [ExportResource]
    let diagnostics: [ExportDiagnostic]
}
```

`CMarkHTMLBodyRenderer` has no shared mutable state. It creates per-call C parser/tree state and returns transient resources to the service for final manifest construction.

`CMarkConfiguration.swift` alone maps `MarkdownDocument.options` to parser option bits/extensions and render option bits/extensions.

**Required cmark ordering:**

1. ensure built-in cmark-gfm extensions are registered through the bounded one-time seam;
2. create parser with configured parser options;
3. find/attach every enabled syntax extension to that parser;
4. feed the complete transformed body;
5. finish to obtain the tree;
6. apply E12 AST policies/mutations;
7. render with the configured render options/extensions;
8. free iterator/tree/parser/rendered C strings on all paths.

Do not parse first and attach table/tasklist/etc extensions afterward.

### Raw HTML and Markdown URL security

Ordinary HTML/PDF must preserve authored raw HTML for fidelity, so render options include `CMARK_OPT_UNSAFE` and GFM `tagfilter`. `tagfilter` is not claimed to be a complete HTML sanitizer.

Because `CMARK_OPT_UNSAFE` also permits cmark-dangerous Markdown link schemes, E12 must traverse **authored cmark link/image nodes before render** through one `ExportURLPolicy`:

- case-insensitive explicit schemes `javascript:`, `vbscript:`, `data:` and `file:` are rejected for authored Markdown nodes;
- relative URLs/fragments and other non-dangerous authored navigation schemes remain available;
- E12-generated embedded `data:` image/CSS references are created only **after** authored URL validation and are not reclassified as authored links;
- image/resource nodes then pass through the stricter destination resource policy in §3.8.

These four dangerous-scheme literals exist only in `ExportURLPolicy.swift`. Do not scatter URL checks through cmark/resource/UI code.

Self-contained HTML additionally fails if the transformed cmark tree contains any remaining authored `CMARK_NODE_HTML_BLOCK` or `CMARK_NODE_HTML_INLINE` before derived custom nodes are installed. This is what makes closure auditable without an HTML crawler.

### Resource types

```swift
public struct ExportResourceID: Hashable, Sendable {
    public let sha256: String       // 64 lowercase hex
    public let mediaType: String    // canonical normalized MIME
}

public struct ExportResource: Sendable {
    public let id: ExportResourceID
    public let filename: String
    public let data: Data
}

public struct ExportManifest: Sendable {
    public let resources: [ExportResource]
    public func resource(for id: ExportResourceID) -> ExportResource?
}
```

Resource identity is `(sha256(bytes), canonical media type)`, not bytes alone. Same bytes + same media type dedupe; same bytes intentionally supplied under different canonical media types remain separate typed resources instead of letting first-seen order choose browser/PDF MIME behaviour.

Companion filename is exactly:

`<64-lowercase-hex-sha256>.<canonical-extension>`

Canonical extension comes from the normalized media type through `UTType.preferredFilenameExtension`; if unavailable use exactly `bin`. CSS has canonical media type `text/css` and therefore `.css`. No original user filename enters durable companion names.

`ExportManifestBuilder` is an **internal per-request mutable builder**, used sequentially by `ExportService` to merge/dedupe body resources and optional linked stylesheet resource. It freezes once into the immutable `ExportManifest`. No builder escapes the request and no second resource array lives in `PreparedExportDocument`.

### Prepared document

```swift
public struct PreparedExportDocument: Sendable {
    public let html: String
    public let manifest: ExportManifest
    public let diagnostics: [ExportDiagnostic]
    public let outputLayout: ExportOutputLayout
}
```

`ExportOutputLayout` has no public general initializer. `make(for: ExportTarget)` validates target and derives all paths/reference modes. `PreparedExportDocument` does not separately store `resources`, `isSelfContained`, a duplicate target URL or other derivable state.

Fatal errors are typed `ExportError`. Non-fatal `ExportDiagnostic` stores machine code/severity/structured context; app target creates localized prose. Package tests never assert English strings.

---

## 3.6 End-to-end data flow

### Phase 0 — app snapshot

On `@MainActor`, immediately before starting work, `ExportCoordinator` captures current text, file URL if saved, `mutationGeneration`, parse options, selected theme, save-panel target/options and latest compatible derived results. Request is then immutable.

### Phase 1 — target/generation validation

- target must be file URL with case-insensitive `.html` or `.pdf` matching target case;
- companion `/dir/report.html` maps exactly to `/dir/report.assets`;
- `Int(exactly: generation)` must succeed for `ParseExecuting`; never wrap/clamp;
- source-size budget checked before parse.

### Phase 2 — fresh MarkdownEngine parse

Call injected parser on immutable text/options/exact revision. Never use preview's debounced `MarkdownDocument`.

Fixed metadata policy:

- non-empty scalar front-matter `title` → escaped browser `<title>` and one visible default-template `<h1>`;
- no front-matter title → browser title from saved Markdown filename stem only;
- filename fallback never synthesizes visible `<h1>`;
- unsaved/no front-matter title → empty browser title;
- invalid/non-scalar title → warning + absent behaviour;
- unknown front-matter keys ignored by E12.

### Phase 3 — output/resource context

Internal reference mode:

- self-contained HTML → `.embeddedData`;
- companion HTML → `.relativeCompanion`;
- PDF → `.localScheme`.

Resource root is only the canonical parent of a saved file URL. Unsaved source has no root.

### Phase 4 — derived validation/substitution

Apply §3.5 derived rules, rewrite declared derived-resource logical references through the same destination/resource rules, then substitute deterministic sentinels back-to-front. Failed/rejected contributions remain source.

### Phase 5 — cmark parse and AST policies

In this exact order:

1. register/configure enabled extensions;
2. create parser + attach enabled syntax extensions;
3. feed/finish transformed body;
4. enforce authored dangerous-URL policy on Markdown link/image nodes;
5. enforce self-contained authored-raw-HTML rejection when applicable;
6. resolve/rewrite ordinary Markdown image resources;
7. replace derived sentinels with custom nodes, using bounded fallback/reparse if needed;
8. render using configured render extensions/options (`UNSAFE + tagfilter` for ordinary authored raw-HTML fidelity);
9. free all C ownership.

### Phase 6 — CSS/template

`ExportService` SwiftPM target processes exactly one structural asset:

`Sources/ExportService/Resources/default-export.css`

Structural/print rules live there. Theme values become deterministic CSS custom properties through one mapper; never duplicate a stylesheet per theme and never interpolate theme display names/user text into CSS.

Packaging:

- self-contained → full generated CSS inline `<style>`;
- companion + embedded CSS → same inline `<style>`;
- companion + linked CSS → generated CSS becomes one managed `text/css` resource and template gets its managed relative reference.

macOS 1.0 has exactly one pure Swift `BuiltInExportTemplate`. No catalog, template ID, protocol hierarchy or discovery mechanism is required yet. It consumes a typed context:

```swift
struct ExportTemplateContext: Sendable {
    let browserTitle: String
    let visibleTitle: String?
    let bodyHTML: String
    let stylesheet: ExportStylesheetPlacement
}
```

It only builds complete HTML5 structure and escapes text/attribute slots; `bodyHTML`/generated CSS are already trusted pipeline products. No Handlebars.

### Phase 7 — manifest freeze/prepared document

Merge body + linked stylesheet resources into one transient `ExportManifestBuilder`, enforce budgets/deduplication, freeze immutable manifest, compose complete HTML, then validate:

- prepared HTML budget;
- unique/sorted resource IDs/filenames;
- no unresolved derived-resource logical marker;
- self-contained has no managed external/local-scheme reference;
- deterministic ordering.

Return one `PreparedExportDocument`.

### Phase 8A — HTML write

`HTMLExportArtifactWriter` is Foundation-only and package-owned.

For self-contained or companion HTML with zero companion resources, atomically promote primary HTML and do not opportunistically touch any old sibling asset directory.

If companion resources exist:

1. asset directory is exactly `report.assets` from layout;
2. marker filename is exactly `.macdown-export-manifest.json`;
3. marker v1 deterministic JSON fields are only:
   - `schema: 1`
   - `producer: "MacDown2.ExportService"`
   - `resources: [sorted current content-address filenames]`
4. existing directory without a valid matching marker is **unknown**: fail before modification;
5. if directory is new, create it and an empty valid marker before resource writes; on failure before primary promotion, best-effort remove only the newly-created managed directory if it still contains no non-E12 names;
6. a valid marker establishes the directory as E12-managed. The reserved managed filename namespace is:
   - the marker itself;
   - writer temporary names generated by `AtomicArtifactWriter` under one fixed hidden prefix;
   - exact `<64hex>.<canonical-extension>` content-address names.
   Every other filename is user/unknown and is never modified/deleted;
7. materialise every new resource first. Existing expected content-address filename inside a managed directory may be reused only after bytes hash and canonical extension/type agree; mismatch is `managedResourceCorrupt` and is not overwritten silently;
8. write new primary HTML to sibling temporary file and atomically promote it;
9. atomically replace marker with new sorted current resource list;
10. after marker commit, best-effort remove reserved content-address files not listed in the new marker. Non-reserved names survive. Cleanup failure is warning only.

A crash may leave reserved orphan content-address/temp files; a later successful companion export may clean only that reserved managed namespace. Do not claim multi-file filesystem atomicity.

### Phase 8B — PDF write

App-side `WebKitPDFRenderer`:

1. `@MainActor`, ephemeral `WKWebViewConfiguration`;
2. JavaScript disabled, non-persistent data store, no injected scripts/service workers;
3. register exactly one E12 scheme handler mapping only manifest IDs → bytes/media type;
4. block network schemes, external navigation, downloads, popups/new windows;
5. load prepared HTML and await terminal load/cancel;
6. freeze `PDFPageLayout` from a copied `NSPrintInfo`; no A4/Letter literals;
7. use `WKWebView.printOperation(with:)` / `NSPrintOperation`, never screenshot/viewport rasterisation;
8. write sibling temporary PDF;
9. PDFKit validate readable document + page count > 0; corpus separately proves searchable text;
10. atomically promote target;
11. teardown web view/scheme state on all paths.

If macOS 26 printing cannot meet searchable/readable pagination, stop Slice 4 and replace only the PDF adapter. Never fork Markdown composition or rasterize as a shortcut.

---

## 3.7 State ownership, concurrency and cancellation

`ExportService` is an immutable `Sendable` value/final type with injected parser, resource/file-system seams needed for deterministic tests and `ExportResourceBudget.standard`. It is not a singleton or global actor. Per-request builders/C trees do not escape calls.

Each document window owns at most one export task; starting a replacement cancels prior task for that window; closing window cancels it; other windows export concurrently.

Only UI snapshot/save-panel state and WebKit/AppKit/PDFKit work are main-actor. Parse/cmark/hash/resource read/Foundation writes run off main actor.

Cancellation checkpoints at minimum:

- before/after fresh parse;
- before/after derived substitution;
- before/after cmark render;
- between resource reads/hashes;
- before template/manifest freeze;
- before each companion resource write;
- before primary promotion;
- before PDF load/print/promotion.

A single C parse/render cannot necessarily be interrupted mid-call; source/output budgets plus Release evidence bound that interval.

Cancel before primary promotion leaves old primary untouched. Cancel after primary promotion during marker/cleanup cannot roll back a valid new primary; it may leave managed orphan files and warning state.

---

## 3.8 Failure semantics and resource policy

### Fatal

- invalid/non-file/wrong-extension target;
- generation cannot exact-convert;
- fresh parse failure;
- source/prepared/resource hard budget exceeded;
- self-contained authored raw HTML;
- self-contained remote/missing/out-of-root/unsupported rendering resource;
- PDF remote/missing/out-of-root rendering resource that would make output knowingly incomplete;
- unknown/unowned required companion directory;
- invalid ownership marker;
- managed content-address corruption;
- filesystem/hash/atomic-promotion failure before commit;
- cmark lifecycle/invariant failure;
- PDF load/print/validation failure.

Fatal failure never replaces existing primary target.

### Non-fatal diagnostics

- invalid front-matter title;
- failed/stale/invalid/overlapping/structurally rejected derived contribution, with source preserved;
- companion HTML remote or unresolved local rendering reference preserved without fetching;
- ordinary HTML raw authored HTML present;
- PDF raw authored HTML present (locked-down host may omit unsupported remote/script-dependent behaviour);
- post-primary marker/cleanup issue that does not invalidate already-written primary/resources.

### Authored Markdown URL policy

Before destination resource logic, cmark Markdown link/image nodes pass `ExportURLPolicy`: authored `javascript`, `vbscript`, `data`, `file` explicit schemes are rejected. Generated resource references are not authored nodes and are created later.

### Navigation vs rendering resources

- ordinary links are navigation and are never fetched by exporter;
- Markdown images/resources are rendering dependencies.

**Companion HTML:** in-root local resource packages. Remote resource URL is preserved semantically but never fetched and warns. Missing/out-of-root local resource remains authored reference and warns.

**Self-contained HTML:** every E12-visible rendering reference must resolve to managed bytes and embed. Remote/missing/out-of-root/unsupported is fatal. Authored raw HTML fatal because arbitrary resource-bearing attributes cannot be proven closed.

**PDF:** every E12-visible rendering dependency must resolve to managed local bytes; remote/missing/out-of-root is fatal. Links remain navigation annotations where print stack supports. Authored raw HTML is best-effort under locked-down WebKit and warns.

### Derived failure

A failed/rejected derived result is never fatal by itself. Preserve exact authored source and emit source-ID/range/reason diagnostic.

---

## 3.9 Security, privacy and trust boundaries

1. No `URLSession`, hosted renderer, default persistent WebKit store or network fetch in first-party export.
2. Local resource root is saved Markdown file's canonical parent only.
3. Standardize/canonicalize URLs and resolve symlinks before containment comparison.
4. Read only regular files; reject directory resources.
5. Snapshot accepted bytes immediately; digest/output use snapshot, not a later path reread.
6. This protects normal traversal/symlink escapes but, like current Preview, does not claim adversarial race-free local filesystem semantics between validation/read; record TOCTOU as residual risk.
7. SHA-256 uses CryptoKit full 64 lowercase hex; never truncate durable names.
8. Normalize media type centrally; canonical extension via `UTType`, fallback `bin`; no scattered extension/MIME switches.
9. `ExportURLPolicy` owns the four dangerous authored Markdown schemes because `CMARK_OPT_UNSAFE` removes cmark's safe-default scrub.
10. Authored raw HTML is trusted authored export content, not app UI; `tagfilter` is retained but not misrepresented as sanitizer.
11. Derived HTML is trusted first-party output admitted later by E14 and must be passive/offline by contract.
12. PDF WebKit independently blocks JS/network/navigation/download/popups and serves only manifest resources.
13. PDF resource URLs never expose arbitrary filesystem paths.
14. Ownership marker parser rejects path separators, `..`, absolute names, duplicate names, unsupported schema/producer and noncanonical listed resource filenames.
15. Unknown directory means no modification. In a marked E12 directory, only reserved managed namespace is mutable; other entries survive.

---

## 3.10 Resource and performance budgets

One `ExportResourceBudget`; no request/call-site literals.

Initial `.standard`:

```swift
public struct ExportResourceBudget: Sendable, Equatable {
    public let maxSourceUTF8Bytes: Int              // 32 MiB
    public let maxResourceCount: Int                // 512
    public let maxSingleResourceBytes: Int          // 32 MiB
    public let maxAggregateResourceBytes: Int       // 128 MiB
    public let maxDerivedFragmentCount: Int         // 4,096
    public let maxAggregateDerivedHTMLBytes: Int    // 32 MiB
    public let maxPreparedHTMLUTF8Bytes: Int        // 128 MiB
}
```

These are initial safety gates, not product semantics. Slice 6 may tune only this definition from measured Release evidence and must record final values. No API/caller changes to tune them.

- count unique `(digest, media type)` resource keys after dedupe;
- overflow-checked byte accumulation;
- derived resources consume ordinary resource budgets;
- derived HTML has own count/aggregate bound;
- no hard-coded PDF page-count limit;
- performance thresholds are Release evidence gates, not normal runtime timeouts;
- tests inject tiny budgets for boundary cases.

Slice 6 records Release evidence for medium document, asset-heavy document, 100+ page PDF, many fake derived contributions, cancellation and peak-memory observation. If in-memory resource snapshot is unsafe at approved limits, stop/revise representation; do not silently unbound reads.

---

## 3.11 Accessibility and localisation

Export UI must be keyboard reachable, VoiceOver-labelled, cancellable and localised. Self-contained selection structurally removes/disables linked-CSS choice; no contradictory hidden state. Progress/cancel uses normal SwiftUI accessibility semantics.

Default HTML template uses semantic HTML5. Front-matter visible title is real `<h1>`, cmark heading/list/table/code/link semantics remain, images retain alt text, CSS preserves visible focus/print contrast. Do not invent language metadata from machine locale.

Derived output may provide accessibility metadata but E12 does not invent renderer-specific labels. PDF acceptance requires searchable/selectable text.

Package diagnostics are machine-readable; app localises prose.

---

## 3.12 Interoperability and future-epic boundaries

### E14

E14 may own richer renderer-neutral lifecycle/capability models, but Export adapter maps them into E12's narrow contract. Shared information required: source identity, original UTF-16 range, `UInt` generation, inline/block placement, passive representation, diagnostics/resources.

### E19

Inline math maps to `.inline`; display math uses `.block` only when its recognized source owns a standalone structural block, otherwise its adapter chooses the placement matching actual range. E12 never recognizes TeX delimiters. Sentinel-before-cmark prevents successful TeX source from being reparsed as Markdown.

### E20/E21

Diagram fences map to `.block` and normally contribute SVG/passive resources. E12 never inspects fence language. Hosted URLs are not a resource escape hatch.

### E11

Do not import Preview to reuse `HTMLPreviewResourceScope`; export owns its boundary. Parity fixtures may use the same traversal/symlink cases.

### E06

Consume `MarkdownDocument`/`SourceMap` without adding export fields to MarkdownEngine. If E14 later proves a cross-module richer range utility is needed, design it there from actual need rather than pre-emptively expanding E06 now.

---

## 3.13 Automated test strategy

Use Swift Testing for MacDownKit and current app test conventions for app-owned code.

### Type/contract

- self-contained + linked CSS unrepresentable;
- PDF cannot carry HTML options;
- no public request layout/budget/metadata/root/template override;
- layout derives `.html/.pdf` and `report.assets` exactly;
- `UInt -> Int` exact overflow path;
- UTF-16 source-range boundary/surrogate cases.

### cmark/config/security

Golden/parity corpus: headings/prose/emphasis/code/quotes/lists, tables/tasks/strikethrough/autolinks/footnotes, links/images, Unicode, raw HTML/tagfilter, options, directives source preservation.

Specific structural tests:

- parser extensions attached before feed/finish and syntax actually parses;
- only `CMarkConfiguration` tests know extension identifiers;
- repeated parse/render/free stress;
- authored Markdown `javascript:`, `vbscript:`, `data:`, `file:` rejected even while raw HTML is rendered with `UNSAFE`;
- relative/http/https/mailto/fragment navigation behaviour remains intentional;
- generated embedded resource data URI remains permitted because it is generated after authored-node validation.

### Derived

- inline fake plain paragraph;
- inline fake inside emphasis/link text;
- inline source containing Markdown-significant characters proves pre-parse shielding;
- block fake top-level;
- block fake nested list/blockquote preserves outer container;
- deterministic sentinel collision;
- stale generation;
- invalid/out-of-bounds/surrogate/front-matter range;
- duplicate/overlap;
- failed result source preservation;
- structural injection rejection + bounded fallback;
- derived-resource rewrite/dedupe/unresolved marker;
- input array order does not change output.

### Metadata/theme/template

- valid title → escaped `<title>` + one `<h1>`;
- absent title → filename browser fallback only;
- unsaved absent → empty title;
- invalid title warning;
- all bundled themes use same mapper/base CSS;
- template/CSS byte determinism;
- linked stylesheet is one typed content-addressed `.css` resource.

### Resources

Temporary dirs + real symlinks:

- in-root relative asset;
- Unicode/spaces;
- `..`, symlink, absolute/file URL escape;
- missing/directory;
- remote zero-network sentinel;
- media type canonicalization + `bin` fallback;
- same bytes/same MIME dedupe;
- same bytes/different MIME deterministic distinct typed resources;
- filename exactly 64hex + canonical extension;
- count/single/aggregate budget boundaries;
- unsaved relative asset;
- self-contained closure failures;
- companion warn/preserve behaviour;
- PDF remote/missing fatal behaviour.

### Companion writer

- new managed directory/marker;
- valid existing marker;
- unknown directory rejected before mutation;
- malformed/unsupported marker;
- nonreserved user files survive;
- reserved orphan content file cleaned only after successful new marker commit;
- expected existing resource verifies hash/type and reuses;
- mismatched reserved resource fails without overwrite;
- fault before resource, mid-resource, before primary, after primary, marker update, cleanup;
- new-dir best-effort rollback before primary;
- cancellation boundaries.

### PDF

- scheme serves manifest IDs only;
- http/https requests blocked with zero-network sentinel;
- JS disabled;
- navigation/download/new-window blocked;
- copied `NSPrintInfo` → layout without paper-size literals;
- PDFKit opens page count > 0;
- representative text searchable;
- local image rendered;
- 100+ pages;
- long code/table usability;
- cancel tears down and preserves old target.

---

## 3.14 Verification and evidence plan

Run from repository root:

```bash
(cd MacDown2 && xcodegen generate)
(cd MacDown2/Packages/MacDownKit && swift build && swift test)
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -configuration Release build
swiftlint lint --strict MacDown2
swiftformat --lint MacDown2
```

PR evidence must include:

1. dependency resolution proving direct exact cmark 0.8.0;
2. package tests;
3. Debug/Release app builds;
4. zero-network sentinel;
5. self-contained browser dogfood;
6. companion re-export/ownership dogfood;
7. PDF Preview.app/PDFKit visual + searchable-text review;
8. Release performance/memory evidence from §3.10;
9. keyboard/VoiceOver/export-panel review;
10. localisation/string review;
11. residual limitations/issues.

Architecture/code inspection alone is not completion; representative HTML/PDF requires human visual review.

---

## 3.15 Adversarial fidelity corpus

At minimum:

1. empty document;
2. ASCII headings/prose;
3. emoji/CJK/combining/non-BMP;
4. HTML escapables;
5. very long code;
6. nested lists/quotes;
7. GFM tables/tasks/strikethrough/autolinks/footnotes;
8. duplicate/reference links/unusual URLs;
9. raw inline/block HTML;
10. tagfilter dangerous tags;
11. dangerous Markdown schemes with `UNSAFE` enabled;
12. front-matter title variants;
13. Unicode local images;
14. missing image;
15. `..` traversal;
16. symlink escape;
17. absolute/file URL;
18. remote image zero-network sentinel;
19. resource budget edges;
20. resource count 512/513 using generated tiny fixtures;
21. same bytes/same MIME dedupe;
22. same bytes/different MIME;
23. self-contained raw HTML rejection;
24. inline fake derived success;
25. block fake + resource;
26. derived failure source fallback;
27. stale/duplicate/overlap/invalid UTF-16;
28. sentinel collision;
29. nested block placement;
30. directives enabled/disabled;
31. untitled dirty doc + relative image;
32. every bundled theme;
33. linked stylesheet typed `.css` resource;
34. known/unknown companion directories + nonreserved user file;
35. write fault injection stages;
36. managed orphan cleanup;
37. 100+ page PDF;
38. PDF local image/remote block;
39. cancellation parse/resource/hash/PDF;
40. cmark lifetime stress;
41. identical complete request repeated → byte-identical prepared HTML/resource names.

---

## 3.16 Expected files and symbol ownership

Do not build a giant `ExportService.swift`.

### `MacDown2/Packages/MacDownKit/Package.swift`

- direct exact cmark 0.8.0;
- cmark products only on ExportService;
- process `Sources/ExportService/Resources`.

### `Sources/ExportService/`

- `ExportService.swift` — orchestration/prepare only.
- `ExportRequest.swift` — source/target/options.
- `ExportResult.swift` — prepared/result if useful.
- `ExportDiagnostic.swift` — errors/codes/context.
- `ExportResourceBudget.swift` — every hard limit.
- `ExportOutputLayout.swift` — target validation/path/reference mode; no public arbitrary initializer.
- `Metadata/ExportMetadataResolver.swift` — fixed title rules.
- `Templates/BuiltInExportTemplate.swift` — one pure typed template; **no catalog**.
- `HTML/CMarkHTMLBodyRenderer.swift` — C parser/tree/render lifecycle only.
- `HTML/CMarkConfiguration.swift` — sole cmark option/extension/registration owner.
- `HTML/ExportURLPolicy.swift` — sole authored dangerous-scheme owner.
- `HTML/DerivedCMarkInjector.swift` — UTF-16 validation, sentinels, custom-node fallback.
- `HTML/ExportStyleSheetBuilder.swift` — base CSS + Theme variables.
- `HTML/HTMLTextEscaper.swift` — template text/attribute slots only.
- `Resources/default-export.css` — structural/print CSS.
- `Assets/ExportResource.swift` — typed digest/media/filename/data.
- `Assets/ExportManifest.swift` — immutable manifest + internal builder.
- `Assets/ExportResourceResolver.swift` — root containment/snapshot/hash/media/budget.
- `Assets/ExportResourceReference.swift` — all generated embedded/relative/local/derived reference literals.
- `Derived/DerivedExportDestination.swift` — generic public destination types.
- `Writing/AtomicArtifactWriter.swift` — single-file atomic promotion + reserved temp prefix.
- `Writing/HTMLExportArtifactWriter.swift` — managed companion/primary sequence.
- `Writing/ExportOwnershipManifest.swift` — exact v1 marker/namespace validation.
- optional `Writing/ExportFileSystem.swift` **only if** the narrow seam is required to deterministically inject filesystem faults in writer/resource tests; do not create a broad virtual filesystem.

Small one-purpose types may colocate with their direct owner if a separate file would be empty ceremony, but ownership must remain as above.

### Tests

`Tests/ExportServiceTests/` mirrors components plus Markdown/expected-HTML fixtures. Generate large/budget binary cases in temporary dirs; do not commit huge blobs.

### App target

- `ExportCoordinator.swift`
- `ExportPanelView.swift`
- `WebKitPDFRenderer.swift`
- `PDFPageLayout.swift`
- composition-root/menu/window/localisation edits
- XcodeGen inputs; never hand-edit project.

### Symbols/structures that must not exist

- `MathExporter`, `MermaidExporter`, `DiagramExporter` in E12;
- renderer-language enum/switch;
- `ExportManager.shared`;
- second prepared resource list beside manifest;
- public arbitrary `ExportOutputLayout(...)`;
- request budget/metadata/resource-root/template selection;
- template catalog/Handlebars/custom template loader;
- network fetch helper;
- screenshot/raster PDF exporter.

---

## 3.17 Serial implementation slices and stop conditions

Workers implement one slice, make its gate green, then review before next.

### Slice 0 — dependency + contracts

**Implement only:** direct cmark dependency/products; request/target/options; diagnostic minimum; budget; output layout; derived destination types; minimal cmark config/lifetime/custom-node smoke.

**Must prove:**

- exact cmark 0.8.0 resolves with current swift-markdown graph;
- only ExportService imports products;
- extension registration, attach-before-parse, render/free repeat safely;
- `CMARK_NODE_CUSTOM_INLINE/BLOCK` and required mutation APIs are available;
- `UInt generation`, no public `Int revision`;
- target owns URL/options, invalid destination states unrepresentable;
- no request layout/budget/metadata/root/template override;
- inline+block anchors compile with UTF-16 range/generation;
- output layout derives `report.assets` and rejects arbitrary/wrong target paths.

```bash
(cd MacDown2/Packages/MacDownKit && swift build && swift test)
```

**Stop/revise:** incompatible cmark graph/API/lifetime, unavailable custom nodes, need for another dependency. Do not add second Markdown library.

### Slice 1 — ordinary deterministic HTML

Implement fresh parse, exact generation conversion, attach-before-parse GFM config, `ExportURLPolicy`, raw HTML policy, metadata, base CSS/theme variables, one built-in template, complete HTML with empty/simple manifest.

Must prove ordinary GFM/Unicode/front-matter/theme corpus, dangerous Markdown links remain scrubbed despite `UNSAFE`, deterministic bytes.

**Stop:** material Markdown divergence cannot be fixed centrally; do not syntax-patch templates.

### Slice 2 — resources + durable HTML

Implement root/containment/snapshot, typed `(digest,MIME)` resources, canonical extensions, manifest builder, self-contained/companion/linked CSS refs, marker namespace, writer sequence, faults/budgets.

**Stop:** requires out-of-root read/network/unknown-directory adoption/nonreserved deletion/truncated hash or new primary can reference unwritten resources.

### Slice 3 — generic derived destination

Implement range validation, deterministic sentinel substitution, custom inline/block injection, same resource manifest, bounded fallback. Test fake only.

**Stop:** requires E14 import, math/diagram parsing, renderer-language switch or second Markdown renderer. Inline support is mandatory now because E19 requires it.

### Slice 4 — PDF adapter

Implement app-side locked WebKit, manifest scheme, system print geometry, print operation, temp PDF, PDFKit validation, network/cancel/100+ page tests.

**Stop:** if macOS 26 print cannot meet searchable/readable pagination; change PDF adapter only.

### Slice 5 — UI/window integration

Implement Markdown-only command, save panel, ThemeController selection, typed packaging controls, current live snapshot at invocation, one task/window, progress/cancel, localized diagnostics.

**Stop:** if implementation requires global current document/export singleton or unowned format.

### Slice 6 — hardening/evidence

Run complete corpus and §3.14 commands/evidence, Release performance/memory, browser/PDF dogfood, offline, a11y/localisation, residual-risk review.

**Stop:** #13 is not complete if acceptance rests on code inspection/agent assertion rather than evidence.

---

## 3.18 Definition of Done and residual risks

Done only when:

- [ ] live current editor snapshot + fresh parse used every export;
- [ ] `UInt` generation preserved/exact-converted only at parser call;
- [ ] typed targets make contradictory states unrepresentable;
- [ ] request excludes layout/budget/metadata/root/template policy;
- [ ] exact cmark 0.8.0 isolated to ExportService and lifetime/custom-node tests pass;
- [ ] GFM extensions attach before parser feed/finish;
- [ ] ordinary HTML parity corpus reviewed/deterministic;
- [ ] raw authored HTML policy exact and dangerous Markdown schemes remain blocked despite `UNSAFE`;
- [ ] title policy exact;
- [ ] all themes flow through one CSS mapper/base stylesheet;
- [ ] self-contained closure enforced for E12-visible resources;
- [ ] resource identity `(full SHA-256, MIME)` and canonical extension deterministic;
- [ ] one immutable final manifest only;
- [ ] companion directory requires marker; reserved namespace only is mutable; nonreserved files survive;
- [ ] resources exist before primary HTML commit;
- [ ] zero network fetch/upload;
- [ ] traversal/symlink/budget tests green;
- [ ] fake inline+block derived output uses one generic sentinel/custom-node path;
- [ ] derived failure/stale/overlap/structural rejection preserves source;
- [ ] derived resources use ordinary manifest/budget path;
- [ ] no production renderer language logic in E12;
- [ ] PDF consumes same prepared HTML, blocks JS/network and uses system geometry;
- [ ] PDF corpus searchable/selectable, local images and 100+ pages visually reviewed;
- [ ] Markdown-only UI snapshots dirty text, cancels correctly, is keyboard/VoiceOver accessible/localised;
- [ ] source never mutated;
- [ ] XcodeGen/package tests/Debug+Release/strict lint+format green;
- [ ] Release performance/memory/offline evidence recorded;
- [ ] owner-readable PR explains changes/test/risk/evidence.

### Residual risks explicitly accepted

1. **cmark parity:** E06 wraps swift-markdown while E12 directly wraps cmark-gfm. Permanent parity corpus is upgrade gate; do not add a second renderer to patch drift.
2. **Block directives:** cmark may not reproduce swift-markdown directive semantics. Preserve authored directive source; do not invent semantics in E12.
3. **Raw HTML trust:** ordinary export preserves authored raw HTML with `UNSAFE + tagfilter`; tagfilter is not a full sanitizer. Markdown-node dangerous schemes are separately blocked. Self-contained rejects raw HTML; PDF locks JS/network. A future stronger raw-HTML sanitization product decision would require its own architecture/dependency review.
4. **Legacy MPAsset:** concrete source contract unavailable; behavioural migration only. Material later evidence is a stop condition.
5. **Issue #35:** non-Markdown parse routing remains separate; export stays Markdown-only.
6. **System PDF stack:** isolated adapter contains WebKit/AppKit variability.
7. **Local filesystem TOCTOU:** canonical containment + immediate snapshot is not a claim of adversarial race-free local filesystem semantics.
8. **Crash orphans:** a crash can leave reserved files in an E12-managed asset directory. Later successful companion export may clean only reserved managed names; correctness takes priority over rollback theatre.
9. **Initial resource limits:** central `.standard` values are provisional safety gates until Slice 6 measured evidence; tuning stays in one definition.

No residual risk permits weakening local/offline operation, source preservation, one-pipeline composition or unknown-user-file protection.

## Explicit Export resource authority — 2 November 2026

The input-authority unit in `downstream/export-input-authority.md` replaces
path approval followed by Data(contentsOf:) with the existing contained reader.
ExportRequest.documentURL is metadata only. ExportResourceAccess retains the
explicit DirectoryLease; the ordinary post-panel snapshot opens it using only
existing process access, without a chooser or broader security scope. The
resolved target leaf supplies image MIME rather than a misleading alias.
Cancellation is bridged to the real cmark thread and 64-KiB read checkpoints.
Serial candidate reads retain per-file, distinct-count and aggregate-payload
limits, deduplication and ordinary-warning versus self-contained/PDF failure.
The disabled SVG fallback preserves this capability and parse policy.

Source-identical Foundation/POSIX controls and hosted package/app validation
are required before integration. Local app/tests compile only. Native/sandbox
acceptance, authorization-time output/source-alias admission, inventory-backed
crash recovery and empirical limits remain separate gates. The optional SVG
route and held preview/current-line changes are not activated.


## Authorization-time destination and immutable PDF bytes — 2 November 2026

The unit in `downstream/export-destination-admission.md` captures the opened
parent and absent-or-regular primary revision before ordinary contribution
parsing/rendering. Publication checks that same admission before staging and
inside the final lifetime cutoff. Current source/open-document URLs and
previously observed FileCore device/inode identities reject aliases, including
hard links whose original source name is gone. Name comparison is deliberately
conservative on case/Unicode variants; it does not normalize source bytes.

Ordinary HTML passes this admission through ExportService. PDF reads a bounded
no-follow candidate relative to the admitted parent, validates/normalizes the
immutable bytes, then publishes those same bytes on an explicitly cancelled
background I/O worker through the shared descriptor-relative primary writer.
Normalization no longer rewrites a printer pathname. Existing PDF integrity
assertions now inspect the accepted value and preserve the input fixture. The
WebKit/NSPrintOperation/fallback API and print-progress policy are unchanged.

This detects observed revision changes and protects the document set captured
at authorization; it is not filesystem compare-and-swap or a global fence
against files opened later. Unknown printer-scratch ownership and automatic
crash repair remain follow-on source/native-probe gates. Full PDF/menu/native
acceptance, Release calibration, final language review and independent release
review remain unperformed. Local app/test targets compile only.

## Bounded resource read work — 2 November 2026

The resolver now caches each parsed root-relative path by exact UTF-8 bytes,
including first refusals. Query, fragment and percent/dot spellings reuse the
same immutable result; authored references still receive individual manifest
mappings. Canonical-equivalent Unicode filenames are not collapsed. Different
filesystem aliases must still use the constrained reader and consume work.
Accepted duplicate content reuses one retained payload value.

One thread-safe reader accounting object bounds an export to provisional 4,096
attempts and 256 MiB of actual positive syscall results. Failed/mutated/non-image
reads consume work too. Each in-flight attempt can read at most one excess
probe byte to detect EOF/growth; exhaustion prevents further attempts. The
existing 512-resource, 32-MiB per-file and 128-MiB distinct-payload ceilings stay
unchanged. Other contained-reader callers retain their existing policy without
an accounting object. Exhaustion retains ordinary warning versus fatal
self-contained/PDF behavior, with a catalogued English reason for final E16.

`downstream/bounded-export-resource-work.md` records the binding source unit,
private real-file controls and limits. This closes repeated input work beyond
distinct-payload accounting; it does not establish empirical final budgets,
crash repair, global late-open document exclusion, printer scratch ownership,
native acceptance or independent release review. Local app targets compile
only and held functionality remains disabled.

## Live document protection and frozen ordinary origins — 3 November 2026

Every ordinary export registers its retained destination admission and weak
lifetime lease before rendering. Incoming controller/CLI-stage pools and changed
tab file identities synchronously check current paths and retained physical file
identities before publishing them. A newly opened alias revokes the export's
publication lease; unrelated opens and keystroke-only edits do not. Inactive
tab insertion is included. The existing lease cutoff linearizes document
publication/revocation against final primary promotion inside this process.

Ordinary origins now have an explicit post-panel frozen-input phase: source,
resource capability, presentation and target are fixed before the first render
await. A Save As or folder change in the same logical tab then leaves those
inputs valid; tab switch/removal and window close still cancel. Pre-panel and
disabled validated origins keep strict identity revocation. No source or UI
retargeting is introduced. The binding source unit and proof limits are in
`downstream/live-export-document-protection.md`. This is not arbitrary external
writer exclusion, filesystem compare-and-swap, crash recovery, printer ownership
or final native acceptance. Local app/UI targets compile only.
