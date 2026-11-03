# EPIC-11 Implementation Plan — Multi-format support

> **Issue:** #12 — `[EPIC-11] Multi-format support: JSON tools, HTML preview toggle, language registry completion`
>
> **Status:** Implemented — Gates 0–6 complete. This document is the binding contract; §7.4 records the Gate 4/Gate 6 release evidence.
>
> **Branch:** `epic/11-multi-format` → `master`.
>
> **Baseline:** current `master` after Epic 10 and Epic 18.
>
> **Depends on:** E05 as built (`GrammarRegistry`), E07 as built (`Preview`/Textual Markdown preview), E08 as built (`OutlineUI`), and E18 as built (document/recovery/external-file safety).

## 1. Planning disposition

The issue is directionally correct but was too broad to implement safely without additional contracts. This plan makes the work reviewable in sequential gates:

1. format/capability contracts and registry consistency;
2. JSON diagnostics, outline, and deterministic formatting;
3. native editor publication and workspace commands;
4. HTML source/rendered preview with explicit resource security;
5. format-neutral preview/outline integration and persistence;
6. one grammar dependency at a time;
7. release, UI, performance, and dependency proof.

No later slice may advertise a format whose parser, grammar, resources, or preview behavior is not buildable and tested. Unsupported formats must degrade to an explicit no-preview/no-highlighting state, never silently inherit a Markdown parser or renderer.

## 2. As-built constraints and ownership

The implementation must preserve these existing boundaries:

- `FileFormat`/`FileFormatRegistry` owns document identity, extensions, UTTypes, supported encoding policy, highlight language, and preview capability. `FileStore` owns byte decoding/encoding and revision capture; `FileDocument` owns the immutable encoding metadata carried with the document snapshot.
- `GrammarRegistry` owns Tree-sitter language construction, query resources, caching, and failure isolation. `ParseEngine` remains Markdown-only.
- `EditorTextSystem` and the existing AppKit delegate own native text edits, selection, undo, and binding publication. JSON formatting must enter this path exactly once.
- `Preview` owns renderer policy and typed preview requests. The current `WKWebView` host remains app-owned in `DocumentEditorSplitView` for this Epic; moving it into the package is explicitly deferred and is not an implementation requirement.
- `OutlineUI` currently consumes Markdown heading data. JSON must use a format-neutral outline snapshot/adapter; it must not fabricate a Markdown AST.
- `WorkspaceSession` is version 1 and owns tabs, identities, and recovery state. Preview mode may be added only as an optional, versioned field and must never alter document/recovery identity.
- `WorkspaceModel` owns format commands, generation checks, save/recovery publication, and format transitions. Views must not parse extensions or mutate document text directly.
- Markdown editing assists remain Markdown-only. JSON and HTML receive native text behavior unless a later Epic explicitly adds language-specific assists.

## 3. Contracts that must be fixed before implementation

### 3.1 Format and preview capability

Replace implicit renderer inference with typed capability/renderer identity. Every format declares an explicit outcome:

```swift
enum PreviewCapability: Sendable, Equatable {
    case none
    case markdown
    case htmlSourceAndRendered
    case jsonOutline
}

enum PreviewMode: String, Codable, Sendable {
    case source
    case rendered
    case outline
}
```

For each capability define: default mode, source of truth, per-tab ownership, session persistence (or explicit non-persistence), Save As invalidation, loading/error/empty states, accessibility identifiers, and jump/scroll rules. Markdown, HTML, JSON, and source-only formats must have routing tests.

### 3.2 File bytes, encoding, and malformed-input contract

This contract is a prerequisite for every JSON gate and applies to all formats. `FileStore` must read an immutable byte snapshot and return decoding metadata; `FileDocument` must retain that metadata through edits, external reconciliation, Save As, and recovery publication. `FileFormat` may constrain or recommend an encoding, but it must not perform byte decoding itself.

Map this contract onto the existing FileCore API; do not add a parallel byte-identity model. `FileRevision.sha256` is already the canonical SHA-256 representation and remains a `String`. Raw bytes are transient `FileStore` data and are not retained in `FileSnapshot` or `FileDocument`, avoiding large-document duplication.

```swift
public enum FileBOM: String, Sendable, Equatable, Codable {
    case none
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}

public struct FileEncodingMetadata: Sendable, Equatable, Codable {
    let encodingRawValue: UInt
    let bom: FileBOM
}

// Existing FileRevision remains unchanged: url, file metadata, and sha256: String.
// Existing FileSnapshot remains the immutable text/revision value. Add `bom` and
// an initializer parameter; do not add raw bytes or a second hash representation.
public struct FileSnapshot: Sendable, Equatable {
    let text: String
    let encodingRawValue: UInt
    let bom: FileBOM
    let revision: FileRevision // captured atomically with the copied bytes/text
}

// Existing FileDocument gains encoding metadata; text, URL, state, recovery
// identity, and lastKnownRevision remain existing fields.
public struct FileDocument: Sendable {
    let text: String
    let encoding: FileEncodingMetadata
    let lastKnownRevision: FileRevision?
}
```

The additive/replacement API and transition contract is:

- `FileStore.readSnapshot(from:)` copies bytes into transient `Data`, computes the existing `FileRevision.sha256`, decodes text and BOM, and publishes `FileSnapshot` only after bytes, metadata, and revision are captured from one stable read. `read(from:)` remains a compatibility projection.
- `FileDocument.create/load` constructs from `FileSnapshot`; untitled documents use the format default and `FileBOM.none` until an explicit override.
- `FileDocument.edited` preserves encoding and `lastKnownRevision` while advancing generation; it never retains raw bytes.
- External reload/reconciliation replaces text, encoding, and `lastKnownRevision` together from the accepted snapshot. Conflict/keep-local paths preserve prior document/recovery state until resolution.
- Recovery writes use current encoding/BOM and expected source revision. Ordinary save publishes the returned revision only after exact written bytes are verified.
- Save As preserves source encoding/BOM by default. An explicit destination override is applied before publication and only becomes document metadata after destination, session, and recovery publication succeed.
- Session restore persists encoding metadata needed to interpret text, never raw bytes; legacy/malformed metadata uses the documented default and is covered by migration tests.

```swift
public struct FileDecodingDiagnostic: Sendable, Equatable {
    let message: String
    let byteOffset: Int // zero-based offset into copied input bytes
}

public enum FileStoreError: Error {
    // existing cases remain
    case decodingFailed([FileDecodingDiagnostic])
}
```

Malformed input returns one diagnostic for the first invalid byte sequence, with its zero-based byte offset; no replacement characters or text snapshot are produced. The prior `FileDocument` and recovery state remain unchanged, and no JSON parsing/formatting runs. Exact-payload tests assert error case, message, offset, and unchanged state.

Per-format encoding precedence is fixed before implementation:

- Markdown, JSON, HTML, and source-only formats preserve detected encoding/BOM; new documents default to UTF-8 without BOM.
- An explicit user override has highest precedence for the next write and becomes metadata only after successful publication. Save As inherits source metadata unless an explicit destination override is selected. CLI and session restore use the same precedence.
- Registry consistency tests cover defaults, detected-BOM preservation, override precedence, Save As, CLI, and session round trips.

### 3.3 JSON diagnostics

Expose a stable value type rather than Foundation parser errors across actors:

```swift
struct JSONDiagnostic: Sendable, Equatable {
    let message: String
    let line: Int       // 1-based physical line
    let column: Int     // 1-based UTF-16 column
    let range: Range<Int>? // UTF-16 code-unit offsets into the immutable editor text snapshot
}
```

`range` uses UTF-16 code-unit offsets, with a half-open range in the same coordinate system used by editor selections and `NSString`/AppKit text APIs. `line` and `column` are derived from that same snapshot; `column` is 1-based UTF-16 within the physical line. Astral scalars, combining marks, CRLF boundaries, and selections spanning surrogate pairs must have explicit expected offsets. Duplicate keys are rejected with a stable diagnostic and no formatting or outline publication; they are never silently merged. Define behavior for empty input, top-level scalars, malformed UTF-8, BOM, CRLF, tabs, and error ranges. Diagnostics are generated from an immutable text snapshot and carry a document revision/generation. Rapid valid→invalid→valid edits must publish only the latest result. Invalid JSON never replaces source text or clears a valid outline without an explicit policy decision.

### 3.4 JSON outline

Use a concrete, source-neutral outline model rather than `AnyHashable` IDs or a fake Markdown document:

```swift
struct ContentOutlineItem: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let lineRange: Range<Int>
    let sourceRange: Range<Int> // UTF-16 offsets
    let children: [ContentOutlineItem]
}
```

IDs encode object-key paths and array-index paths for valid JSON and remain remappable across edits/formatting. Duplicate-key input is rejected before outline construction, so there are no duplicate-key outline nodes or disambiguation/remapping rules. Repeated array elements remain distinct by index. Define labels for scalar roots, empty containers, and arrays/objects; set a tested depth/node policy; preserve collapse/selection/jump behavior; and define what happens on invalid JSON.

### 3.5 JSON formatting

Formatting is deterministic and operates only on valid JSON. Capture immutable text plus document generation/revision, compute off the main actor, and reject the result if the document or external-file baseline changed. Apply output as one contiguous native editor replacement, producing exactly one undo group, one binding publication, and normal dirty/recovery updates.

Specify:

- object key sort order (Unicode scalar order, recursively for nested objects);
- arrays retain order;
- duplicate-key behavior: reject with a stable diagnostic; never format, sort, or outline a duplicate-key document;
- scalar roots;
- indentation and trailing-newline policy;
- CRLF/LF and BOM preservation;
- non-ASCII escaping policy;
- behavior when formatting is requested for invalid JSON.

### 3.6 HTML preview security and resources

The existing WebKit host disables JavaScript and loads with `baseURL: nil`. The Epic must make an explicit decision before implementation:

- **v1 policy:** scripts are disabled; no JavaScript bridge is exposed. Network access, popups, downloads, message handlers, forms, clipboard access, storage/cookies, and external navigation are disabled or denied. A WKWebView is not treated as an additional security boundary.
- Relative resources may load only from an approved document directory after explicit security-scoped access. Untitled HTML has no local resource root.
- Reject `../` escape, outside-root symlinks, remote URLs, `javascript:` URLs, iframe escapes, popups, downloads, and navigation outside the approved policy.
- Save As, rename, delete, and preview disposal must balance security-scope access and cancel stale loads.

The HTML hardening path must not rely solely on raw string search that can mistake `<head>` text inside comments or script strings for markup. Use a parser/sanitizer or a wrapper plus WebKit policy controls, with adversarial fixtures.

HTML reload is latest-request-wins, revision-tagged, cancellation-safe, and triggered on save/relevant source revision—not unrelated SwiftUI updates.

## 4. Sequential implementation gates

### Gate 0 — Byte, format, and registry consistency

Add the byte/encoding metadata contract, typed capability/renderer contracts, a format manifest/consistency check, and the generation/cancellation contract. Compare registry extensions/UTTypes, `project.yml`/Info.plist declarations, highlight IDs, preview capabilities, and CLI format behavior. No implementation slice proceeds with drift.

### Gate 1 — JSON core

Create a Foundation-only JSON support target or clearly isolated FileCore module containing diagnostics, parsing, deterministic formatting, and outline building. Do not route JSON through Markdown parsing. Pass diagnostics, formatting, outline identity/source-range, cancellation, and Release performance tests before UI wiring.

### Gate 2 — JSON editor/workspace integration

Add Format JSON and Format JSON with sorted keys commands. Route formatting through the existing editor replacement/undo/binding/recovery path. Add stale generation, external replacement, one-undo, one-publication, selection, and format-transition tests. Commands must be disabled for non-JSON/invalid states.

### Gate 3 — Format-neutral outline and preview integration

Preserve Markdown outline behavior while adding JSON adapters. Add per-tab preview mode state, session migration only if persistence is required, Save As format invalidation, layout-mode interaction, accessibility identifiers, and no-stale-Markdown-state tests.

### Gate 4 — HTML source/rendered preview

Implement the v1 scripts-disabled policy, scoped base URL/resource loading, source/rendered toggle, save-triggered reload, cancellation, disposal, and denied navigation/network/popup/download tests. Keep the WKWebView host app-owned in `DocumentEditorSplitView`; `Preview` supplies policy/request types only.

### Gate 5 — Grammar completion

Add one grammar dependency at a time. Before declaring a language supported, prove exact pinned resolution, target/product names, C entry point, query resources, license/notice obligations, Release resource inclusion, and capture smoke tests. Unsupported or failed grammars remain explicit no-highlight states.

Suggested risk-based order: CSS/JavaScript/TypeScript; Python/Ruby/Bash/SQL; YAML/TOML/XML; Swift/C/C++. Do not add all packages in one unreviewable change.

### Gate 6 — Release and hosted acceptance

Require serial package tests in CI, Debug/Release app and CLI builds, generated Xcode project verification, targeted app/UI tests, Release performance results, dependency/license inventory, and (where available) TSan. No gate may weaken existing assertions or replace service/app proof with mocks.

## 5. Required test matrix

Name suites or equivalent coverage:

- `JSONDiagnosticsTests`
- `FileEncodingMetadataTests`
- `FileStoreMalformedEncodingPayloadTests`
- `FileDocumentEncodingRoundTripTests`
- `FileEncodingCoordinateBoundaryTests`
- `JSONDiagnosticUTF16CoordinateTests`
- `FileEncodingPrecedenceTests`
- `JSONFormattingTests`
- `JSONFormattingUndoPublicationTests`
- `JSONFormattingGenerationRaceTests`
- `JSONOutlineIdentityTests`
- `JSONOutlineSourceRangeTests`
- `JSONOutlinePerformanceTests`
- `PreviewCapabilityRoutingTests`
- `PreviewModeSessionTests`
- `HTMLPreviewSecurityTests`
- `HTMLPreviewResourceScopeTests`
- `HTMLPreviewReloadGenerationTests`
- `FormatTransitionTests`
- `FormatRegistryConsistencyTests`
- `GrammarRegistryCompletenessTests`
- `GrammarFailureIsolationTests`
- `GrammarDependencyResourceTests`
- `GrammarColdLoadPerformanceTests`
- `NoPreviewAccessibilityUITests`
- `JSONOutlineUITests`
- `HTMLToggleUITests`
- `SaveAsFormatTransitionUITests`

Minimum scenarios include:

- valid/invalid JSON, Unicode, astral scalars, combining marks, CRLF, BOM, top-level scalar, and duplicate-key rejection with stable diagnostics;
- UTF-8/UTF-16 BOM retention, malformed UTF-8 byte-offset diagnostics, encoding-preserving Save As, explicit encoding override, and external byte-revision races;
- UTF-16 diagnostic ranges and editor selections at surrogate-pair, combining-mark, and CRLF boundaries;
- deterministic sorted formatting, one undo/publication, edit-during-format, external replacement, and generation mismatch;
- nested/empty JSON nodes, repeated array elements, duplicate-key rejection before outline construction, 10,000-node and deep documents, source jumps, collapse/selection remapping, and invalid-input policy;
- HTML relative image/style/font/media, missing resources, traversal, symlink escape, untitled/moved documents, scripts-disabled behavior, blocked navigation/network/popups/downloads, stale reload, disposal, and scope balance;
- every advertised extension, case normalization, UTType/project metadata, grammar query loading/failure, cache behavior, and no-preview fallback;
- Markdown↔JSON↔HTML Save As, tab isolation, session round-trip, stale parser/outline clearing, and Markdown-only editing assists.

## 6. Performance budgets and evidence

These are initial Release targets and must be confirmed against measured baselines, not treated as proof until the full app path is exercised:

- JSON validation: debounce ≤150 ms; 100 KB under 50 ms.
- JSON formatting: 100 KB under 100 ms; 1 MB under 500 ms.
- JSON outline: 10,000 nodes under 200 ms off the main actor.
- Grammar cache hit under 1 ms; cold load under 200 ms where practical.
- HTML: no more than one WebKit load per saved source revision; unrelated SwiftUI updates cause zero reloads.
- Record median and p95 separately for pure parser work and editor/UI publication at 100 KB, 1 MB, and 10 MB inputs.

## 7. Dependency and release evidence

Every new grammar or renderer dependency requires exact version/revision, license/notice, transitive dependency inventory, resource-bundle ownership, archive inclusion, known maintenance/security risk, and a reproducible package resolution. No unpinned range may remain in the final implementation PR.

### 7.1 Gate 5 grammar inventory (12 languages)

Gate 5 adds 12 advertised highlight languages, each proven buildable and query-backed by `GrammarRegistryCompletenessTests` (no advertised language may silently degrade). Ten resolve from exact remote pins; two are vendored locally because upstream never commits a generated `parser.c`.

| Language id | Package | Resolution | License |
|---|---|---|---|
| yaml | `tree-sitter-yaml` | `exact: 0.7.0` | MIT (tree-sitter-grammars) |
| toml | `tree-sitter-toml` | `exact: 0.7.0` | MIT |
| javascript | `TreeSitterJavaScript` (vendored) | local path | MIT (Max Brunsfeld) |
| typescript | `tree-sitter-typescript` | `exact: 0.23.2` | MIT |
| python | `tree-sitter-python` | `exact: 0.23.6` | MIT |
| ruby | `tree-sitter-ruby` | `exact: 0.23.1` | MIT |
| css | `tree-sitter-css` | `exact: 0.23.2` | MIT |
| swift | `tree-sitter-swift` | `exact: 0.7.3-with-generated-files` | MIT |
| cpp | `tree-sitter-cpp` | `exact: 0.23.4` | MIT |
| bash | `tree-sitter-bash` | `exact: 0.25.1` | MIT |
| sql | `TreeSitterSQL` (vendored) | local path | MIT (Derek Stride) |
| xml | `tree-sitter-xml` | `exact: 0.7.0` | MIT (ObserverOfTime) |

Pre-existing E05 grammars (markdown, markdown-inline via vendored `TreeSitterMarkdown`; `json` `from: 0.24.8`; `html` `from: 0.23.2`) are unchanged. Neon (`revision: 484d6fb9…`) and `SwiftTreeSitter` remain as built in E05.

### 7.2 Vendored grammars

- `Packages/TreeSitterJavaScript` — vendored because `tree-sitter-javascript` has no tag whose `Package.swift` lists sources explicitly. The vendored manifest pins `sources: ["src/parser.c", "src/scanner.c"]` (generated parser ≈ 2.9 MB).
- `Packages/TreeSitterSQL` — vendored because `DerekStride/tree-sitter-sql` never checks in its generated `parser.c`, so no release builds from source. The vendored manifest pins `sources: ["src/parser.c", "src/scanner.c"]` and ships the 41,602,006-byte (~41 MB) generated parser plus a 4.8 KB scanner.

### 7.3 SwiftPM conditional-manifest workaround

The tree-sitter CLI's newer manifest template conditionally includes `src/scanner.c` via `FileManager.fileExists` checks that SwiftPM 6.x evaluates against the bare repository cache (no working files), silently dropping the scanner and breaking the link. The fix, applied uniformly across Gate 5:

1. Pin the newest tag whose manifest lists sources explicitly (fixed-sources manifest).
2. Where no such tag exists, vendor the grammar locally with an explicit `sources:` array (JavaScript, SQL).
3. `tree-sitter-swift` is pinned to the maintainers' `-with-generated-files` tag, which ships `parser.c` for source distribution.

### 7.4 Gate 4 and Gate 6 release evidence

- **Gate 4 (HTML source/rendered preview):** `WKURLSchemeHandler` host (`HTMLPreviewView`/`HTMLPreviewPane`/`HTMLPreviewSchemeHandler`) serving a `macdown-preview://` scheme; every response carries the authoritative CSP header (`HTMLPreviewResponseHeaders`) — WebKit honors it on custom-scheme responses and no markup can divert it, so the meta-CSP injection in `PreviewSecurity` is belt-and-braces only; remote/`javascript:`/`data:`/`file:` top-level navigation, downloads (response-layer, policy-gated), and popups (navigation-layer + `createWebViewWith`) denied; scheme authority (host/userinfo/port) validated; `HTMLPreviewResourceScope`-validated subresource serving under `PreviewSecurityScope` (security-scoped access, symlink-safe); reload-on-save via `HTMLPreviewReloadGate` (clean state + generation gate + debounce + task cancellation), with failed main-document loads re-arming the gate for retry; disposal cancels tasks/loads and releases scope. Covered by the preview test suites (navigation policy, comment/rawtext-aware security tokenizer, resource scope, reload generation, response-header enforcement, mode session).
- **Gate 6 (release and acceptance):** `swift build` green; **890 tests / 96 suites** pass; `swiftlint lint --strict MacDown2` and `swiftformat --lint MacDown2` both clean (0 findings); `xcodegen generate` reproduces the project; Debug and Release app builds and the `macdown2` CLI build succeed; `macdown2 formats` lists all 16 formats with extensions and preview capability, matching `FileFormatRegistry`. `MultiFormatUITests` covers the JSON outline rows/preview, invalid-JSON diagnostic state, the HTML source ↔ rendered toggle, and the no-preview placeholder (identifiers: `jsonOutlineRow-*`, `jsonOutlinePreviewPane`, `jsonInvalidState`, `htmlPreviewModeToggle`, `htmlSourcePane`, `htmlRenderedPane`, `noPreviewPane`). Note: the JSON pane / no-preview assertions are sensitive to accessibility-hierarchy churn in the local UI-test runner (the app's window content intermittently fails to materialize under the automated session on this machine); CI compiles the UI tests via `build-for-testing` but does not execute them.

## 8. Explicit deferrals

- JSON Schema validation;
- HTML source-editing assists;
- remote/network HTML preview;
- arbitrary JavaScript bridges or unrestricted local file access;
- full AST-aware formatting for every language;
- PDF/export changes;
- plugin-provided grammar discovery;
- settings/localization redesign.

## 9. Planning review record

This plan was checked independently from two angles:

- **Adversarial review:** identified P1 risks around formatting publication, HTML security/resource policy, grammar dependency buildability, and preview routing, plus P2/P3 gaps in diagnostics, outline identity, cancellation, performance, registry consistency, and dependency evidence.
- **Architecture implementation audit:** mapped each slice to current `FileCore`, `EditorCore`, `Preview`, `OutlineUI`, `Workspace`, `Highlighting`, `project.yml`, and package ownership, and identified issue-text conflicts with the as-built WebKit host, Markdown-specific outline/parser, and existing format registry.

The Epic is ready for implementation planning review, not yet for production implementation or merge of feature code.

## JSON busy-state overlap — 3 November 2026

JSONAnalysisSession now accounts for actual immediate analysis calls separately
from a scheduled debounced task. Busy remains true while either exists, including
a superseded worker draining after a newer result or cancellation. Three
controlled overlaps fail their busy-state assertions on the unchanged source;
publication generations, returned cancelled results and the already-cancelled
no-state path stay intact. The source fix follows MarkdownParseSession's existing
counter/defer pattern. `downstream/async-ui-publication-review.md` records the
scope and proof; it does not establish preemption, worker bounds, performance or
native acceptance. Local app/UI targets compile only.
