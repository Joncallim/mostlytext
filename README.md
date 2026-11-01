# MacDown 2

> **Website:** [mostlytext.app](https://mostlytext.app)

A native macOS Markdown editor — a ground-up Swift / SwiftUI rewrite built on
TextKit 2, a modular Swift package core, and a modern SwiftUI shell.

> **Status:** active development, feature epics in progress (updated
> 2026-09-18). Implemented and merged: project foundations, file/format
> core, the native-`NSWindow`-tab workspace shell, the TextKit 2 editor,
> tree-sitter highlighting and the theme system, the native Markdown parser
> and block-sliced Textual preview, the heading outline and lazy folder
> browser, JSON/HTML multi-format support, Markdown editing assists,
> HTML/PDF export with a shared derived-content destination, a native
> SwiftUI Settings scene, first-party contribution infrastructure (table of
> contents, local text-filter commands, command palette), live
> external-file change detection/conflict handling, first-class
> math/scientific-notation rendering ($…$ / $$…$$) in preview and export,
> and a native diagram platform supporting Mermaid, D2, and Graphviz/DOT
> (```mermaid```/```d2```/```dot``` fences rendered natively in preview and
> exported as genuine vector SVG). WaveDrom was evaluated and deliberately
> deferred, not rejected, over a real `eval()`-based code-execution risk in
> its documented rendering API — see issue #46.
>
> Known open work before macOS 1.0: a narrower external-file-change
> notice-banner issue is tracked as
> [#70](https://github.com/Joncallim/macdown_2/issues/70) (the core
> defect, #59, is fixed); a narrower Preview-only math/nested-code-fence
> edge case is tracked as
> [#63](https://github.com/Joncallim/macdown_2/issues/63); none of the
> three diagram languages has an interactive copy-as-SVG affordance yet
> ([#86](https://github.com/Joncallim/macdown_2/issues/86)); a genuine,
> pre-existing (not newly introduced) fragility across roughly half of the
> `MacDown2UITests` target was found and is being triaged
> ([#88](https://github.com/Joncallim/macdown_2/issues/88)). The remaining
> planned epics — whole-app accessibility and polish, localisation, and
> signed/distributable release engineering — have not started. See
> [`planning/epics/README.md`](planning/epics/README.md) for the full epic
> table and [`planning/RELEASE_EVIDENCE.md`](planning/RELEASE_EVIDENCE.md)
> for the release-readiness ledger, which distinguishes "implemented" from
> "release-proven" per epic.

## Requirements

- macOS 26.0 or later
- Xcode 26 (Swift 6.2 toolchain, strict concurrency)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated, not committed

## Repository layout

```
MacDown2/
├── MacDown2/                 # App target (SwiftUI shell)
├── MacDown2CLI/              # `macdown2` command-line tool
├── MacDown2UITests/          # XCUITest target
├── Packages/MacDownKit/      # Swift package — all logic lives here
│   └── Sources/
│       ├── FileCore          # FileStore, FileFormat registry, document lifecycle
│       ├── Workspace         # Per-window model + session restore (native NSWindow tabs)
│       ├── EditorCore        # NSTextView + TextKit 2 editor
│       ├── Highlighting      # Tree-sitter engine (markdown/json/html), Neon-backed
│       ├── Themes            # Theme model + Tomorrow Light/Dark, live switching
│       ├── MarkdownEngine    # Native swift-markdown parser + parse session store
│       ├── Preview           # Block-sliced native Textual preview + scroll sync
│       ├── OutlineUI         # Heading outline: tree, selection, identity remap, controller
│       ├── FileTree          # Folder browser: lazy tree, FS watching, CRUD (E09)
│       ├── AppSettings       # Typed settings model + panes (E13)
│       ├── ExportService     # HTML/PDF export + shared derived-content destination (E12)
│       ├── Contributions     # First-party contribution SPI/registry: TOC, etc. (E14)
│       ├── TextFilters       # Local text-filter command execution (E14)
│       ├── JSONSupport       # JSON analysis/outline (E11)
│       ├── Math / MathRendering   # Inline/display math parsing + rendering (E19)
│       ├── Diagrams / DiagramRendering  # Mermaid diagram platform: model + WKWebView renderer (E20)
│       ├── DiagramWebKitPool     # Shared offscreen WKWebView pool generalized for E21's renderers
│       ├── DiagramsD2 / D2Rendering            # D2 diagram support (E21)
│       ├── DiagramsGraphviz / GraphvizRendering  # Graphviz/DOT diagram support (E21)
│       └── …
├── Packages/TreeSitterMarkdown  # Vendored markdown + markdown-inline grammars
└── project.yml               # XcodeGen project definition
planning/                     # Epic specs and implementation plans
legacy-reference/             # Legacy ObjC MacDown — read-only porting source
```

## Building

```bash
# 1. Logic package — build + test (all unit tests live here)
cd MacDown2/Packages/MacDownKit
swift build
swift test

# 2. Generate the Xcode project
cd ../..
xcodegen generate

# 3. Build the app and the CLI
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2  -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2CLI  -destination 'platform=macOS' build
```

## Linting

```bash
swiftformat --lint MacDown2
swiftlint   lint --strict MacDown2
```

CI (`.github/workflows/ci.yml`) runs the lint, package tests, and app/CLI builds
on every push and PR to `master`.

## Roadmap

Development is organised into epics, each tracked as a GitHub issue with a spec in
[`planning/epics/`](planning/epics/) and a detailed implementation plan in
[`planning/`](planning/). See [`planning/MIGRATION_PLAN.md`](planning/MIGRATION_PLAN.md)
for the overall plan.

## License

MacDown 2 is free and open-source software, released under the [MIT License](LICENSE).

It is an open-source **fork and successor of [MacDown](https://github.com/MacDownApp/macdown)**,
the original macOS Markdown editor by Tzu-ping Chung and contributors (also MIT-licensed).
The original copyright notice is retained in [`LICENSE`](LICENSE).
