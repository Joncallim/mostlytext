# EPIC-21 implementation architecture: Evaluate/integrate D2, Graphviz/DOT, WaveDrom

Baseline `master` SHA: `dd679b3` (2026-09-17, E20 fully merged through Slice
6). Product contract: GitHub issue #46. Depends on E20 (done: issue #45,
PRs #74-#80).

This document does two things per `EPIC_STANDARD.md`'s architecture gate:
records the required admission-review decision for each candidate (§1-§4,
grounded in real, cited research — not general impressions), and specifies
the implementation architecture for whichever candidates are accepted
(§5 onward). Per the epic's own explicit framing (`RELEASE_HARDENING.md`
§4, issue #46): "an evidence-backed rejection is a valid E21 outcome and
must not hold macOS 1.0 hostage" — this document accepts two of three
candidates and defers the third with a specific, falsifiable reason.

---

## 1. Research basis

Findings below come from directly inspecting each candidate's real,
current npm-published artifact (tarball contents, byte sizes, license
files) and its public repository/CVE history — not from general
familiarity. Every factual claim carries a citation. Researched
2026-09-17/18.

### 1.1 D2 (d2lang.com)

- **Official browser build**: yes — `@terrastruct/d2` on npm, published
  from inside the `d2lang/d2` monorepo itself (`d2js/d2wasm`/`d2js/js`),
  not a third-party wrapper. Runs the Go-compiled WASM off the main
  thread in a Web Worker. ([npm](https://www.npmjs.com/package/@terrastruct/d2),
  [pkg.go.dev](https://pkg.go.dev/github.com/d2lang/d2/d2js/d2wasm))
- **Artifact**: `dist/browser/index.js` from the real
  `@terrastruct/d2@0.1.33` tarball — one file, **~7.8 MiB**, WASM embedded
  inline (no separate `.wasm` to co-locate).
- **License**: MPL-2.0 (confirmed in the repo's own `LICENSE.txt`) — weak,
  file-level copyleft. A "Larger Work" combining unmodified MPL files with
  proprietary files does not require the proprietary side to be
  open-sourced. ([LICENSE.txt](https://github.com/terrastruct/d2/blob/master/LICENSE.txt),
  [Mozilla MPL-2.0 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)) As of
  D2 0.9.0 (2026-09-07), the previously-proprietary TALA layout engine was
  open-sourced under the same MPL-2.0 and folded in with no license key
  required. ([d2lang.com/blog](https://d2lang.com/blog/tala-is-open-source/))
- **Maintenance**: very active — last push 2026-09-15 (two days before
  research), company-backed (Terrastruct), 25,450 stars.
  ([d2lang/d2](https://github.com/d2lang/d2))
- **Security**: parser/compiler is Go (memory-safe); no CVEs found
  against it. Runs inside the WASM sandbox regardless.
- **Output**: native SVG. Recent D2 versions have moved label rendering
  away from `<foreignObject>` toward native SVG text — the exact failure
  mode this app already hit and fixed for Mermaid
  (`RenderedMermaidDiagram`'s own doc comment) — suggesting D2's SVG
  *may* display correctly via AppKit's native decoder without the
  raster-PNG-snapshot fallback Mermaid needed. Not yet verified against
  real D2 output; treated as an open question for Slice 0/1, not assumed.

**Decision: ACCEPT.** Clean license, strong security posture, official
first-party WASM, active company-backed maintenance, and the same
integration shape already proven for Mermaid.

### 1.2 Graphviz / DOT

Two independent, real (not reimplemented) WASM wrappers around the actual
Graphviz C core exist:

- **`@viz-js/viz`** (Mike Daines, long-running, widely used — Observable
  and others depend on it): real tarball inspected —
  `dist/viz-global.js` = **~1.26 MB**, a plain-`<script>`-tag IIFE build,
  no bundler required. API: `Viz.instance()` → `.renderString(dot,
  {format:'svg'})`. Last push 2026-09-02, 4,348 stars.
  ([mdaines/viz-js](https://github.com/mdaines/viz-js))
- **`@hpcc-js/wasm-graphviz`** (HPCC Systems/LexisNexis): real tarball
  inspected — `dist/index.js` = **~800 KB**, WASM embedded inline. Last
  push 2026-09-16 (the day before research).
  ([hpcc-systems/hpcc-js-wasm](https://github.com/hpcc-systems/hpcc-js-wasm))

**License nuance — the actual due-diligence finding here**: both
packages' own npm `license` field (Apache-2.0 for hpcc-js,
MIT for viz-js) describes only the *wrapper*. The compiled artifact in
both cases embeds Graphviz's own C source, and Graphviz itself is
licensed **EPL-2.0** (relicensed from CPL-1.0 in 2026-03).
([graphviz.org/license](https://graphviz.org/license/)) viz-js's own docs
disclose this ("since Viz.js is a derivative work, it is released under
EPL too"); hpcc-js's npm metadata does not mention it at all. EPL-2.0 is
weak, module-level copyleft — bundling the unmodified library in a closed
app does not require the app's own source to be disclosed, but EPL
notices/attribution for the Graphviz portion specifically must be
carried, independent of what the wrapper's own `license` field claims.
([Eclipse Public License — background](https://fossa.com/blog/open-source-software-licenses-101-eclipse-public-license/))

- **Maintenance**: both active (see push dates above).
- **Security**: Graphviz's native C parser has a real, recurring CVE
  history from crafted DOT input — stack overflows in `scan.l`/`parser.y`,
  an out-of-bounds read via a crafted config file, a `shapes.c` overflow
  documented as recently as August 2025.
  ([CVEDetails: Graphviz](https://www.cvedetails.com/vulnerability-list/vendor_id-3872/Graphviz.html))
  Compiling to WASM and running inside the same offscreen, sandboxed
  `WKWebView` pool this app already uses for Mermaid contains a
  memory-corruption bug in the parser inside the WASM linear-memory
  sandbox — it cannot pivot to native code execution or file/process
  access the way an `NSTask`-invoked native `dot` binary could. This is
  the identical trust model already accepted for Mermaid (a large,
  complex JS parser/renderer, sandboxed the same way) — not a new risk
  category for this app.
- **Output**: native SVG using plain `<text>`/`<path>`/`<ellipse>`
  elements — **not** `<foreignObject>`-based. This should render
  correctly via AppKit's native SVG decoder without needing Mermaid's
  raster-PNG-snapshot fallback (verify empirically, Slice 1, before
  relying on it — matching E20's own "spike before committing" lesson).

**Decision: ACCEPT**, via `@viz-js/viz` — smaller ecosystem footprint risk
than choosing between two viable options arbitrarily, its own docs
disclose the EPL nuance directly (a transparency point in its favor), and
its plain-global-script build matches this app's `loadFileURL` pattern
with zero bundler tooling. `@hpcc-js/wasm-graphviz`'s smaller artifact
size is noted as a secondary option if `viz-js`'s WASM footprint or
maintenance posture changes materially before implementation.

### 1.3 WaveDrom

- **Official browser JS**: yes, and the simplest of the three — pure
  JavaScript, no WASM, no native binary. `wavedrom.min.js` = **~54 KB**
  (or `wavedrom.unpkg.min.js` ~99 KB bundled with a default skin).
  ([wavedrom/wavedrom](https://github.com/wavedrom/wavedrom))
- **License**: MIT — fully permissive, no copyleft on either side.
- **Maintenance**: active but single-lead-maintainer since 2011 (Aliaksei
  Chapyzhenka); last push 2026-08-31, 205 open issues — a real bus-factor
  and issue-backlog signal relative to D2 (company-backed) and both
  Graphviz wrappers (organizational or long-established backing).
- **Security — the finding that drives this decision**: WaveDrom's
  documented, advertised top-level API
  (`WaveDrom.ProcessAll()` → `eva(id)`) parses its WaveJSON input via
  `source = eval('(' + TheTextBox.value + ')')` — inspected directly in
  `lib/eva.js` on the current `master` branch, marked
  `/* eslint-disable no-eval */` as a deliberate design choice, not an
  oversight. This means the documented entry point executes arbitrary
  JavaScript found in a fenced code block's text.
  ([lib/eva.js](https://github.com/wavedrom/wavedrom/blob/master/lib/eva.js))
  This exact mechanism was assigned **CVE-2026-50733** against a
  different Markdown previewer ("Markdown Preview Enhanced," a VS Code
  extension) that rendered WaveDrom fences via this same path, yielding
  arbitrary JS execution and, from there, arbitrary file write, from
  nothing more than previewing a crafted Markdown document.
  ([VulnCheck advisory](https://www.vulncheck.com/advisories/markdown-preview-enhanced-arbitrary-code-execution-via-wavedrom-eval))
  This is precisely the feature shape this app would build — a fenced
  code block rendered by a Preview pipeline against arbitrary
  user-authored (or received/opened) Markdown.
- **A safe path exists but is not the documented one**: WaveDrom
  separately exports `renderWaveForm(index, source, output,
  notFirstSignal)`, which accepts an *already-parsed* JS object rather
  than a raw string — bypassing `eva()`/`eval()` entirely if the
  integrating app parses WaveJSON itself with a strict parser first.
  However, WaveJSON's own accepted grammar is deliberately looser than
  strict JSON (it documents JS-expression shortcuts, e.g. multiplying a
  repeated wave state) specifically because `eval()` is the reference
  parser — a from-scratch strict-JSON5 reimplementation risks silently
  rejecting or mis-parsing legitimate WaveDrom documents that rely on
  those shortcuts, which is a real compatibility gap on top of the
  security rework, not just a drop-in substitution.
- **Output**: native SVG, no `foreignObject` — same AppKit-decoder
  advantage as Graphviz, if it were integrated.

**Decision: DEFER, not rejected outright.** The documented API is a real,
first-party, CVE-precedented code-execution risk for exactly this app's
feature shape (rendering fenced blocks from arbitrary opened documents).
A safe API exists, but using it requires this app to design, implement,
and maintain its own WaveJSON-superset parser reconciled against
WaveDrom's actual (not merely nominally-JSON) accepted input grammar —
real, open-ended design work disproportionate to a niche (digital timing
diagrams, a narrower EE/hardware audience than D2/Graphviz's general
technical diagramming) relative to the two accepted candidates, which
have no analogous parser-security problem to solve at all. This is not a
permanent rejection of WaveDrom as a diagram language; it is a decision
that the specific engineering investment needed (a safe WaveJSON parser,
verified against real compatibility) is not proportionate to take on in
the same pass as D2/Graphviz, and is better left as an explicit, separate,
future decision if there is a specific reason to want it (see issue
filed in §18-equivalent tracking below). Silence-by-omission was
considered and rejected: the epic's own acceptance criteria require "a
documented accept/reject decision" for each candidate, so this is
recorded as a real decision with a real, falsifiable reason, not left
implicit.

---

## 2. What "accepted" means concretely

Per issue #46's own scope section, each accepted candidate:

- integrates through E20's diagram contract (`Contributing`, the
  offscreen-`WKWebView`-pool pattern, the shared cache);
- defines fenced-code-block language aliases consistently
  (```` ```d2 ```` for D2; ```` ```dot ````/```` ```graphviz ```` for
  Graphviz — both are real, commonly-used aliases in other tools);
- inherits E20's cancellation/cache/diagnostic/vector-export/
  accessibility rules rather than reinventing them;
- is verified for real Release-build responsiveness with multiple
  renderer kinds mixed in one document.

---

## 3. Architecture: generalize the pool, keep per-language contributions separate

### 3.1 What is shared vs. per-language

E20 built exactly one instance of a pattern this epic now needs twice
more: an offscreen, sandboxed `WKWebView` pool running a bundled JS
library against untrusted text, returning a plain JSON-shaped result.
Rather than copy `MermaidWebRenderer`/`MermaidHarnessPage` twice more
nearly verbatim (three near-identical actors each reimplementing
pool/checkout/checkin/timeout logic), this epic generalizes the *pool and
page lifecycle* into shared, renderer-agnostic infrastructure, while
keeping each language's own `Contributing` implementation, fence scanner,
and JS harness completely separate — because those three things
genuinely differ per language (different JS invocation shape, different
result parsing, different error semantics, different fence-language
aliases) and forcing them into one shared abstraction would be exactly
the kind of premature generalization this project's own conventions
warn against (`AGENTS.md`/this document's own house style: no abstraction
built for a hypothetical fourth renderer that isn't part of this epic).

**New shared package, `DiagramWebKitPool`** (replaces nothing —
`MermaidWebRenderer`/`MermaidHarnessPage` are NOT retroactively rewritten
to use it; see §3.3 for why):

```swift
/// One offscreen, sandboxed page running one bundled JS harness, reused
/// across many calls. Generic over nothing — callers get a raw
/// evaluate-and-parse hook, not a typed render API, because that
/// per-language typing is exactly the part this type does NOT own.
@MainActor
final class DiagramHarnessPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    static func make(
        harnessResourceName: String,
        bundle: Bundle
    ) async throws -> DiagramHarnessPage

    /// Evaluates `functionBody` (a callAsyncJavaScript body, exactly
    /// MermaidHarnessPage's own pattern) with `arguments` bound directly
    /// — never string-interpolated — and returns the raw bridged result.
    func evaluate(_ functionBody: String, arguments: [String: Any]) async throws -> Any?

    func teardown()
}

/// A bounded pool of DiagramHarnessPages, identical checkout/checkin/
/// timeout logic to MermaidWebRenderer's own (§11 of epic-20-
/// implementation.md) — extracted here because THIS part, unlike JS
/// invocation shape, is genuinely identical across every renderer this
/// app has or will add.
public actor DiagramWebKitPool {
    public init(poolSize: Int = 2, timeout: Duration = .seconds(5),
                admissionTimeout: Duration? = nil)
    public func withPage<T: Sendable>(
        _ body: @escaping @Sendable (DiagramHarnessPage) async throws -> T
    ) async throws -> T
    public func shutdown() async
}
```

The current implementation keeps the five-second default for JavaScript
execution after page acquisition. The separately bounded default admission
window is 15 seconds for pool queueing, cold harness navigation and optional
renderer preparation; an
explicitly longer execution budget is not shortened during admission.

The resource-backed pool initializer also accepts an optional async
`preparePage` callback, executed before acquisition under the same admission
window. A failed/canceled preparation tears down its unpublished page. D2 uses
this callback to await its single page-owned engine's `ready` promise; every
later compile/render pair reuses that worker under the pool's existing exclusive
page ownership. This does not change either timeout ceiling or the vendor
bundle. See [D2 engine lifetime](downstream/d2-engine-page-lifetime-2026-11-03.md).

Each language's own renderer (`D2WebRenderer`, `GraphvizWebRenderer`)
owns one `DiagramWebKitPool` instance, its own bundled harness resource,
and its own `evaluate(...)` call shape/result parsing — mirroring exactly
what `MermaidWebRenderer`/`MermaidHarnessPage` already do today, just with
the pool/page plumbing factored out instead of copy-pasted.

### 3.2 New packages, following E20's exact naming/dependency shape

- **`DiagramsD2`** (pure Swift: `D2Fence`, `D2FenceScanner`,
  `D2RenderContext`, `RenderedD2Diagram`, `D2RenderError`,
  `D2DiagramRendering` protocol, `D2DiagramCache`, `D2Contribution`) —
  depends on `MarkdownEngine`, `Contributions`. Mirrors `Diagrams`
  (Mermaid's pure-Swift package) exactly, one file-for-file.
- **`D2Rendering`** (WebKit-dependent: `D2WebRenderer`,
  `D2HarnessPage`-equivalent, the bundled `@terrastruct/d2` browser
  build + harness HTML/JS) — depends on `DiagramsD2`,
  `DiagramWebKitPool`.
- **`DiagramsGraphviz`** / **`GraphvizRendering`** — identical shape for
  `@viz-js/viz`'s `viz-global.js`.
- **`DiagramWebKitPool`** (new, shared, WebKit-dependent, no
  language-specific code) — depended on by `D2Rendering` and
  `GraphvizRendering` only; `DiagramRendering` (Mermaid's own package,
  already shipped) is **not** retrofitted onto it — see §3.3.

### 3.3 Why Mermaid's existing renderer is not refactored onto the shared pool

`MermaidWebRenderer`/`MermaidHarnessPage` already ship, are already
covered by real, passing tests, and already work. Refactoring shipped,
tested infrastructure to share code with a *new* epic's needs is a real
risk (any subtle behavioral difference introduced during extraction — an
error path, a teardown-ordering detail — regresses a working feature for
a refactor with no user-visible benefit) for a benefit (some duplicated
pool/checkout code) that does not outweigh it. If a future epic needs a
fourth renderer, retrofitting Mermaid onto the shared pool at that point
(when the shared abstraction has two real, independent consumers proving
it generalizes correctly, not just one) is the more defensible order of
operations. Recorded explicitly so this is a deliberate choice, not an
oversight discovered in review.

### 3.4 Fence language detection

`D2FenceScanner`/`GraphvizFenceScanner` mirror `MermaidFenceScanner`
exactly (walk `document.blocks` recursively for `.codeBlock(language:)`,
match case-insensitively) with one difference: Graphviz accepts **two**
common aliases, ```` ```dot ```` and ```` ```graphviz ````, both mapped
to the same renderer — both are genuinely widely used across other tools
(GitHub itself, various static-site generators) and rejecting one in
favor of the other would be a real, avoidable interoperability gap for
documents authored elsewhere.

### 3.5 Preview display: verify per-language before assuming Mermaid's fallback is needed

§1.1/§1.2 both flag that D2's and Graphviz's native SVG output (no
`foreignObject`) may render correctly via AppKit's own SVG decoder,
unlike Mermaid's. This must be verified for real (a spike identical in
spirit to E20 Slice 4's) before deciding each renderer's Preview display
path:

- **If AppKit renders it correctly**: `D2DiagramBlockView`/
  `GraphvizDiagramBlockView` can display `RenderedD2Diagram.svg`
  natively (via `NSImage(data:)`), giving genuinely resolution-independent
  on-screen vector display — a real improvement over Mermaid's raster
  fallback, not merely parity with it.
- **If it does not** (some Graphviz shape or D2 feature turns out to hit
  an AppKit SVG-decoder gap `RenderedMermaidDiagram` didn't): fall back
  to the identical real-WebKit-raster-snapshot technique already proven
  for Mermaid (`render.js`'s canvas/`toDataURL` approach), and each
  `Rendered*Diagram` type still carries both `svg` and `pngData` from one
  render call, exactly like Mermaid's.

This is Slice 1's first concrete task for each renderer — named here as
an open question, not asserted as fact, matching this document's own
epic-20 predecessor's discipline about not asserting an unverified
rendering-fidelity claim.

### 3.6 Export wiring

`ContributionRegistry.standardForExport` (`MathExportRegistry.swift`,
already extended once for Mermaid) gains `D2Contribution` and
`GraphvizContribution` alongside `MathContribution`/`MermaidContribution`
— same file, same array, matching E20's own precedent of keeping exactly
one real factory function rather than a competing registry per epic.

### 3.7 Security containment

Identical layered model to Mermaid (epic-20-implementation.md §10),
applied per language:

- `websiteDataStore = .nonPersistent()`, `loadFileURL(_:
  allowingReadAccessTo:)` scoped to exactly the bundled harness
  directory, a navigation delegate that cancels anything outside it, a
  UI delegate that denies popups — all inherited free from
  `DiagramHarnessPage` (§3.1), not reimplemented per language.
- D2 and Graphviz's own harness CSPs mirror Mermaid's exactly
  (`script-src 'self'; connect-src 'none'; ...`) — neither library needs
  network access to render, so the same total-network-denial posture
  applies without exception.
- Graphviz specifically: the WASM sandbox is the primary containment for
  the real, cited C-parser CVE history (§1.2) — this is not a new
  containment layer invented for Graphviz, it is the existing
  `DiagramHarnessPage` isolation already relied on for Mermaid's own,
  independently large attack surface.
- D2 specifically: no known parser-level CVEs, but the same containment
  applies regardless — untrusted input gets the same treatment whether or
  not a known vulnerability class exists yet.

---

## 4. Non-negotiable invariants

Identical to epic-20-implementation.md §4, extended to both new
languages: document content never leaves the device; authored source is
the only durable representation; a failed/timed-out/unavailable renderer
degrades that block only, never the document or another block; rendering
never blocks `MainActor`; a superseded render is discarded, never
overwrites a newer result; Export renders through the exact same
`Contributing` → `ExportDerivedContribution` → `DerivedContentComposer`
path as every other contribution — no parallel exporter per language.

---

## 5. Implementation slices

Mirrors epic-20-implementation.md §17's structure and discipline
(named spikes for genuine unknowns, explicit stop conditions) rather than
re-deriving a new process from scratch.

### Slice 0 — Spike: AppKit SVG-decoder fidelity for real D2 and Graphviz output

**Goal**: render one representative D2 diagram and one representative
Graphviz/DOT diagram through their real WASM builds (a throwaway spike,
not committed — same method as epic-20's Slice 0/4 spikes), capture the
real SVG output, and test `NSImage(data:)` rasterization against it the
same way epic-20 Slice 4 did for Mermaid.

**Decision output required**: for each of D2 and Graphviz, independently:
"AppKit renders this correctly — native SVG display" or "AppKit fails
this the way it failed Mermaid — raster-snapshot fallback needed," with
the actual before/after evidence (not asserted from documentation alone,
matching §3.5's own stated discipline).

> **As-built note (Slice 0, 2026-09-18):** done, both decisions are
> "AppKit renders correctly." A real `digraph{A->B;B->C;A->C;}` through
> the actual `@viz-js/viz@3.30.0` bundle, and a real `A -> B -> C`
> through the actual `@terrastruct/d2@0.1.33` bundle, both produced SVG
> with zero `<foreignObject>` elements, and both rasterized via
> `NSImage(data:)` into fully correct, correctly-labelled, correctly-laid-out
> images — confirmed visually, not merely "decoded without error." Neither
> D2 nor Graphviz needs Mermaid's raster-PNG-snapshot fallback;
> `RenderedD2Diagram`/`RenderedGraphvizDiagram` need only `svg` — no
> `pngData` field, unlike `RenderedMermaidDiagram`. §3.5's provisional
> language is resolved in the more favorable direction for both.
>
> **A second, real finding changes §3.2/§3.3's loading plan for D2
> specifically:** `@terrastruct/d2`'s official browser build is a genuine
> ES module (`export{... as D2}`, confirmed by inspecting the real
> tarball). Loading it via `<script type="module">` and an internal
> `import('./d2-browser.js')` — the natural approach — fails with
> `TypeError: Cross-origin script load denied by Cross-Origin Resource
> Sharing policy`, even though the page itself loads fine via
> `loadFileURL(_:allowingReadAccessTo:)` and even though the *top-level*
> module script executes (confirmed via a try/catch around the dynamic
> `import()`, which is what surfaced this exact error text rather than a
> silent failure). This is a real, current WebKit `file://` restriction
> on ES module sub-imports specifically, distinct from ordinary
> `<script src>` resource loading (which this app's harnesses, including
> Mermaid's and viz-js's own plain-global-script builds, already rely on
> without issue). **Resolution**: the vendored `d2-browser.js` resource is
> not the untouched upstream file — it is upstream's own file with its
> single trailing `export{lw as D2}` statement mechanically replaced by
> `window.D2=lw;`, turning it into an ordinary global-assigning script
> loadable exactly like every other bundle this app already vendors. This
> is a real modification to an MPL-2.0-covered file; MPL-2.0's file-level
> copyleft requires that modified file's source stay available, which it
> already is (a plain, readable, committed resource file in this
> repository, not obfuscated or built through an opaque pipeline) — the
> patch itself is called out explicitly in that file's own leading
> comment (Slice 2) and here, not left to be discovered by reading a diff.
> Nothing else about the file is altered — no minification, no other
> content change — so the WASM payload and D2 version remain exactly
> upstream's own build.

### Slice 1 — `DiagramWebKitPool` (shared) + `DiagramsD2`/`DiagramsGraphviz` (pure Swift)

**Goal**: the shared pool/page type (§3.1), and both languages' pure
model/scanner/cache/contribution layers (§3.2), fully unit tested against
fake renderers — zero WebKit dependency, mirrors epic-20 Slice 1 exactly.

**Stop condition**: if extracting the pool from `MermaidWebRenderer`'s
existing, shipped logic would require changing that file's own behavior
(not just literally copying its checkout/checkin/timeout shape into a
new, separate type), stop and reconsider §3.3's premise — the intent is
duplication-avoidance for new code, never at the cost of touching shipped
behavior.

### Slice 2 — `D2Rendering` + `GraphvizRendering` (real WebKit renderers)

**Goal**: real, non-mocked renderer implementations for both languages,
bundling the actual pinned `@terrastruct/d2` and `@viz-js/viz` browser
builds (exact versions pinned, LICENSE files vendored, matching Mermaid's
own precedent), with real tests exercising genuine WASM execution —
correct rendering, malformed-source handling, timeout, output-size
ceiling, pool recovery, concurrent pool usage — one test suite per
language, mirroring `MermaidWebRendererTests`' exact structure.

**Stop condition**: if either WASM build fails to load/execute reliably
under `swift test` (unlikely given Slice 0 of epic-20 already proved
`WKWebView`+WASM-adjacent JS execution works in a package-test host, but
not proven for these SPECIFIC multi-megabyte WASM payloads), stop and
re-run epic-20's own Slice-0-style investigation before proceeding
further with that language.

> **As-built note (Slice 1-2, 2026-09-18): the stop condition's own
> caveat fired for real** — real WASM payloads under a real CSP surfaced
> three genuine failures Mermaid's own (non-WASM) harness never needed to
> solve, found via temporary `stderr` instrumentation in
> `DiagramHarnessPage` (removed before the final commit, same discipline
> as epic-20's own temporary `os_log` tracing for #59):
>
> 1. **`script-src 'self'` alone refuses `WebAssembly.compile`/
>    `instantiate`.** viz-js failed immediately and cleanly with
>    `Refused to create a WebAssembly object because 'unsafe-eval' or
>    'wasm-unsafe-eval' is not an allowed source of script`. Fix: add
>    `'wasm-unsafe-eval'` to `script-src` in both `D2Rendering`'s and
>    `GraphvizRendering`'s harness CSP — this permits WASM compilation
>    specifically and nothing broader (string-to-JS `eval()` stays
>    blocked by it alone). This alone fully fixed Graphviz.
> 2. **D2 needed a second, distinct fix**: with only fix 1 applied, D2
>    still failed — not with a clean rejection, but with WebKit's
>    `evaluateJavaScript`/`callAsyncJavaScript` eventually reporting
>    "Completion handler for function call is no longer reachable" (the
>    Swift side waiting indefinitely for a reply that never arrives).
>    Root cause: D2 spawns its real compute worker via
>    `new Worker(URL.createObjectURL(new Blob([...])))`, and the CSP had
>    no `worker-src` directive, which falls back to `default-src 'none'`
>    — silently refusing to start the worker at all, with no exception
>    surfaced back through the `postMessage` channel D2's own JS uses to
>    talk to it. Fix: add `worker-src blob:` to `D2Rendering`'s harness
>    CSP specifically (Graphviz has no worker and needs no such
>    exception).
> 3. **A third, real, separate finding, uncovered only once 1 and 2 were
>    both fixed**: an actual render then failed cleanly with `Refused to
>    evaluate a string as JavaScript because 'unsafe-eval' ... is not an
>    allowed source` — D2's own compiled output genuinely uses a
>    string-to-JS `eval()`/`new Function(...)` call somewhere in its
>    Go-to-JS/WASM bridge glue, independent of the WASM-specific
>    permission already granted. This is a materially broader CSP grant
>    than either Mermaid or Graphviz needs — recorded as a real, named
>    trade-off (not silently added): accepted specifically because the
>    harness's OTHER containment (no network access at any layer, no
>    file access beyond this one resource directory, and an output that
>    is only ever treated as inert SVG text afterward, never
>    re-executed) already bounds what a full script-execution compromise
>    of this one sandboxed, disposable page could do — it could not
>    escalate beyond producing a maliciously-shaped SVG string, a failure
>    mode every other layer of this pipeline already has to tolerate.
>    `D2Rendering`'s harness CSP is therefore genuinely different from —
>    not merely a superset of — Mermaid's and Graphviz's; this is called
>    out directly in the harness HTML's own comment, not left to be
>    discovered by diffing CSP strings across the three harnesses.
>
> All three fixes are applied only to the specific harness(es) that
> needed them — Mermaid's own CSP (epic-20-implementation.md §10) is
> completely untouched. Full evidence: all 7 `D2WebRendererTests` and all
> 7 `GraphvizWebRendererTests` pass for real (previously, before fix 2,
> the abandoned-task timeout test took ~6846 seconds to "pass" — Swift's
> structured-concurrency task groups wait for cancelled children to
> actually finish before returning, so a genuinely hung child task made
> the whole timeout mechanism appear to work while actually blocking for
> nearly two hours; after the fix, the same test passes in ~4 seconds).

### Slice 3 — Export wiring

**Goal**: `D2Contribution`/`GraphvizContribution` added to
`ContributionRegistry.standardForExport` (§3.6), real end-to-end tests
mirroring `MermaidExportRegistryTests` exactly for each language.

### Slice 4 — Preview wiring

**Goal**: extend `TextualMarkdownPreview`'s `BlockView` with two more
fence-language branches (```` ```d2 ````, ```` ```dot ````/
```` ```graphviz ````) alongside the existing Mermaid one, each backed
by whichever display mechanism Slice 0 determined (native SVG or raster
fallback, decided per-language, not assumed uniform).

**Stop condition**: identical in spirit to epic-20 Slice 4's — if
`BlockView`'s current structure has diverged since this document was
written, re-read the live file before extending it rather than assuming
the shape described here still matches.

**As-built (PR #84)**: `BlockView`'s structure had not diverged; the
described extension applied directly. Confirmed the display-mechanism
decision from Slice 0 for both languages: neither needs a raster
fallback, since a real spike proved D2's and Graphviz's plain-element
SVG output (no `<foreignObject>`) displays correctly via AppKit's own
`NSImage` decoder — `D2DiagramBlockView`/`GraphvizDiagramBlockView`
display `svg` directly, simpler than `MermaidDiagramBlockView`'s
pngData/canvas-rasterization path. One deviation from the epic-20
precedent: extending `BlockView` with two more fence branches pushed
`TextualMarkdownPreview.swift` over SwiftLint's `file_length` limit
(404 lines), so `BlockView` (previously `private`, file-scoped) was
extracted into its own file, `TextualMarkdownPreview+BlockView.swift`,
with its access level widened from `private` to internal (`struct`) so
the main file can still construct it. `D2FenceContent`/
`GraphvizFenceContent.stripDelimiters(from:)` were factored out of
their respective `FenceScanner`s in the same commit, mirroring
`MermaidFenceContent`'s existing shape, so Export's scanner-based
stripping and Preview's block-based stripping share one implementation
per language. Real evidence: full package suite 1266/1266, app-target
suite 159/159 (serial, including two new `*PreviewIntegrationTests`
suites exercising real parse → slice → strip → shared-renderer →
real-SVG-assertion for each language), Debug + Release builds of both
app and CLI schemes all succeed, `swiftformat`/`swiftlint --strict`
clean. Live GUI dogfood of the wired Preview pane was not attempted
this slice — same disclosed environment gap already recorded for
Mermaid — deferred to Slice 6 alongside that existing gap.

### Slice 5 — Adversarial hardening + mixed-renderer performance

**Goal**: adversarial corpus per language (empty/malformed/oversized
source, at minimum — mirroring epic-20 §15's exact categories), plus a
real test opening one document containing Mermaid, D2, and Graphviz
fences together, confirming independent failure isolation and that
Release-build responsiveness holds with three renderer kinds active in
one document (acceptance criterion: "mixed accepted-renderer documents
remain responsive").

**As-built (PR pending)**: mirrored epic-20 Slice 5's own precedent
exactly — a moderately complex, realistic diagram (containers/clusters,
multiple node shapes, styled connections) and a whitespace-only-source
case added to `D2WebRendererTests`/`GraphvizWebRendererTests`. One real
finding from doing this empirically rather than assuming Mermaid's
pattern transfers unchanged: whitespace-only source is *valid* D2 (an
empty document is a legal, deliberate D2 language feature) but *invalid*
DOT (Graphviz requires a `graph`/`digraph` keyword) — so D2's test
asserts safe completion with a real (near-empty) SVG, while Graphviz's
asserts the same `.self`-typed failure as its malformed-syntax test,
not a shared assumption. The other epic-20 §15 categories (rapid
sequential edits, language-tag transitions, aggregate export-budget
ceiling) are not separately re-tested per language for the same reason
epic-20 gave: they exercise SwiftUI's own `.task(id:)` cancellation or
E12's own generic budget machinery, not per-language code.

The mixed-document test (`MixedDiagramRendererIntegrationTests`, app
target) renders Mermaid + D2 concurrently (real, distinct sources —
deliberately never reused from any other test in the process, since
`ContributionRegistry.shared*Renderer` are process-lifetime caches and
an identical source would silently short-circuit to a cache hit rather
than a real render, understating the evidence) alongside a deliberately
invalid Graphviz fence, via three `async let` bindings. Confirmed for
real: the invalid fence fails on its own (caught, asserted `nil`)
without blocking or corrupting the other two languages' independent
results, and all three complete in ~1.9s wall-clock with three distinct
`WebContent` processes visibly spawned concurrently in the test log —
not serialized behind one shared pool.

### Slice 6 — Definition of Done

**Goal**: real UI-test evidence (mirroring epic-20's own honest treatment
of that gap if the same environment limitation recurs), `RELEASE_EVIDENCE.md`
E21 row, `planning/epics/README.md`/`README.md` reconciliation, and an
explicit WaveDrom-deferral note recorded in the epic issue itself (§1.3's
decision, restated as a closing comment on issue #46, not left only in
this document).

**As-built**: the "if the same environment limitation recurs" hedge
turned out not to apply — this session's environment allowed genuine
XCUITest execution for the first time. `D2GraphvizPreviewUITests` (new,
mirroring `MermaidPreviewUITests`'s exact shape: valid/malformed ×
D2/Graphviz, 4 tests) ran for real via `xcodebuild test-without-building`
and passed 4/4. As a direct side effect of the environment cooperating,
`MermaidPreviewUITests` (E20's own long-`unverified` suite) was also
re-attempted and passed 2/2 for real — retroactively resolving that E20
evidence gap too, recorded in `RELEASE_EVIDENCE.md`'s E20 row rather than
only here.

Running the full `MacDown2UITests` target once execution was possible
surfaced a genuinely new, unrelated finding: 15 of the other 30 tests
(across `EditingAssistsUITests`/`EditorTypingUITests`/
`ExternalFileChangesUITests`/`FolderBrowserUITests`/`MultiFormatUITests`/
`OutlineNavigationUITests`) fail when actually executed. Verified this is
not a regression from this epic's own work: checked out `dd679b3` (the
commit immediately before EPIC-21 started) in an isolated `git worktree`
and reproduced one representative failure
(`MultiFormatUITests.testPlainTextShowsNoPreviewPlaceholder`) identically
against that pre-EPIC-21 code. Filed as
[#88](https://github.com/Joncallim/macdown_2/issues/88) rather than
silently left as a footnote — this project's UI-test suite has
apparently never actually been run to completion before, since CI
documents the whole target as build-only and every prior local attempt
was blocked before getting this far.

Reconciling this epic's own acceptance criteria ("Accepted renderers
preserve vector output for preview/export... Source↔preview navigation
and copy/export behave consistently across accepted renderers") against
the shipped code alongside E20's own AC found the same real gap in both
epics: no interactive copy-as-SVG affordance exists for any diagram
language (Mermaid, D2, or Graphviz) despite it being a literal,
explicit criterion. Filed as
[#86](https://github.com/Joncallim/macdown_2/issues/86), scoped to cover
all three languages together since they share the same gap and fix
shape. Not fixed in this slice.

WaveDrom's deferral decision was already posted as a comment on issue
#46 during the architecture phase (before Slice 0 began) — re-confirmed
present and unchanged rather than re-posted, satisfying the Definition
of Done's intent (recorded on the issue itself, not left only in this
document) without duplicating it.

`RELEASE_EVIDENCE.md`'s E21 row reconciled to `done` with full Slice
1-6 evidence; `planning/epics/README.md`'s E21 row updated to ✅ done.
`README.md`'s status blurb and package-layout listing reconciled in the
same pass. Issue #46 closed with a comment mirroring this project's
established EPIC-13/#53 and EPIC-20/#45 precedent: core scope done and
evidence-backed, both real residual gaps (#86, #88) have their own
dedicated tracking rather than being silently dropped.

---

## 6. Definition of Done

- [x] D2 and Graphviz each pass every relevant test row from §5's slices;
      WaveDrom's deferral decision (§1.3) is posted as a comment on issue
      #46, not left implicit.
- [x] Per-language AppKit-vs-raster display decision (§3.5) made from
      real evidence, not assumed from Mermaid's own outcome (both
      languages: direct SVG display, no raster fallback needed).
- [x] `swift test`/`xcodebuild test` green for every new suite; full
      existing suites unaffected (regression-free) — 1270/1270 package,
      160/160 app-target serially, plus now-genuinely-executed
      `D2GraphvizPreviewUITests` (4/4) and `MermaidPreviewUITests` (2/2).
      A separate, pre-existing, non-regressive UI-test fragility finding
      (15/30 other `MacDown2UITests`) is tracked as #88, not silently
      folded into "unaffected."
- [x] `swiftformat --lint`/`swiftlint lint --strict` clean.
- [x] Debug and Release builds succeed (app and `macdown2` CLI, both
      configurations).
- [x] A mixed-renderer document (Mermaid + D2 + Graphviz) is verified
      responsive and each renderer fails independently
      (`MixedDiagramRendererIntegrationTests`, ~1.9s wall-clock, three
      real concurrent `WebContent` processes).
- [x] `planning/RELEASE_EVIDENCE.md`, `planning/epics/README.md`,
      `README.md` reconciled against real, current state.

Consciously deferred:

- WaveDrom (§1.3) — a real, specific, falsifiable reason, not a stalled
  decision; revisit only via an explicit new product decision, not by
  quietly attempting it inside a later epic.
- Exact per-language timeout/output-size-ceiling defaults are provisional
  pending real-diagram calibration, matching epic-20's own §11/§18
  precedent.
- Theme-color wiring for D2/Graphviz — same disclosed, deliberate scope
  limit already recorded for Mermaid (issue #79); not solved here either.
