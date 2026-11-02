// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacDownKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FileCore", targets: ["FileCore"]),
        .library(name: "CommandBridge", targets: ["CommandBridge"]),
        .library(name: "LocalResourceAccess", targets: ["LocalResourceAccess"]),
        .library(name: "AppSettings", targets: ["AppSettings"]),
        .library(name: "Themes", targets: ["Themes"]),
        .library(name: "Workspace", targets: ["Workspace"]),
        .library(name: "FileTree", targets: ["FileTree"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "Highlighting", targets: ["Highlighting"]),
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
        .library(name: "Preview", targets: ["Preview"]),
        .library(name: "OutlineUI", targets: ["OutlineUI"]),
        .library(name: "JSONSupport", targets: ["JSONSupport"]),
        .library(name: "ExportService", targets: ["ExportService"]),
        .library(name: "Contributions", targets: ["Contributions"]),
        .library(name: "TextFilters", targets: ["TextFilters"]),
        .library(name: "Math", targets: ["Math"]),
        .library(name: "MathRendering", targets: ["MathRendering"]),
        .library(name: "Diagrams", targets: ["Diagrams"]),
        .library(name: "DiagramRendering", targets: ["DiagramRendering"]),
        .library(name: "DiagramWebKitPool", targets: ["DiagramWebKitPool"]),
        .library(name: "DiagramsD2", targets: ["DiagramsD2"]),
        .library(name: "D2Rendering", targets: ["D2Rendering"]),
        .library(name: "DiagramsGraphviz", targets: ["DiagramsGraphviz"]),
        .library(name: "GraphvizRendering", targets: ["GraphvizRendering"]),
        .library(name: "TextSearch", targets: ["TextSearch"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", branch: "main"),
        .package(url: "https://github.com/Joncallim/Neon", revision: "dabf50c947148c49acd0d321dfe8f3805d10b3da"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.2"),
        // EPIC-11 Gate 5 grammars. Every grammar is pinned exactly; see
        // planning/epic-11-implementation.md §7 for the per-grammar evidence.
        //
        // Versions chosen deliberately: the tree-sitter CLI's newer manifest
        // template conditionally includes src/scanner.c via
        // `FileManager.fileExists`, which SwiftPM 6.x evaluates against the
        // bare repository cache (no working files), silently dropping the
        // scanner and breaking the link. The newest tags with fixed-sources
        // manifests are pinned instead; tree-sitter-javascript has no
        // fixed-sources manifest in any tag, so it is vendored locally
        // (Packages/TreeSitterJavaScript).
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml", exact: "0.7.0"),
        .package(path: "../TreeSitterJavaScript"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
        // tree-sitter-swift does not check its generated parser.c into normal
        // tags; the maintainers ship `-with-generated-files` tags for source
        // distribution, which is what the SPM package needs.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", exact: "0.23.4"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.25.1"),
        // tree-sitter-sql is vendored locally: DerekStride/tree-sitter-sql
        // never checks in its generated parser.c, so no release builds from
        // source. See Packages/TreeSitterSQL/README.md.
        .package(path: "../TreeSitterSQL"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-xml", exact: "0.7.0"),
        .package(path: "../TreeSitterMarkdown"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.8.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.13.9"),
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
        .package(url: "https://github.com/Joncallim/textual", revision: "d3ddabb1da37681083cdc3da706f96cf2fb6a3c6"),
        // Only a transitive dependency of `textual` (via its own Package.swift)
        // until this pin: `textual` does not re-export `SwiftUIMath` as one of
        // its own products, so `MathRendering` (below) needs this explicit,
        // same-version pin to import it directly (epic-19-implementation.md
        // §16). Pinned to the exact version the Textual fork itself requests
        // (`from: "0.1.0"`), so SwiftPM resolves one shared copy, not two.
        .package(url: "https://github.com/gonzalezreal/swiftui-math", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "FileCore"),
        .target(name: "CommandBridge", dependencies: ["JSONSupport"]),
        .target(name: "LocalResourceAccess"),
        .target(name: "TextSearch", dependencies: ["FileCore"]),
        .target(name: "AppSettings", dependencies: ["JSONSupport"]),
        .target(name: "Themes", resources: [.process("Themes")]),
        .target(name: "Workspace", dependencies: ["FileCore", "JSONSupport"], resources: [.process("Resources")]),
        .target(name: "FileTree", dependencies: ["FileCore"], resources: [.process("Resources")]),
        .target(name: "EditorCore", dependencies: ["FileCore", "TextSearch"], resources: [.process("Resources")]),
        .target(
            name: "Highlighting",
            dependencies: [
                "EditorCore",
                "Themes",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
                .product(name: "Neon", package: "Neon"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterMarkdown"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterJavaScript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterSQL", package: "TreeSitterSQL"),
                .product(name: "TreeSitterXML", package: "tree-sitter-xml"),
            ]
        ),
        .target(
            name: "MarkdownEngine",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "Preview",
            dependencies: [
                "MarkdownEngine",
                "Themes",
                "FileCore",
                "Diagrams",
                "DiagramsD2",
                "DiagramsGraphviz",
                .product(name: "Textual", package: "textual"),
            ]
        ),
        .target(name: "OutlineUI", dependencies: ["MarkdownEngine", "JSONSupport"]),
        .target(name: "JSONSupport", dependencies: [], resources: [.process("Resources")]),
        .target(
            name: "ExportService",
            dependencies: [
                "MarkdownEngine",
                "Themes",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "Contributions", dependencies: ["MarkdownEngine"], resources: [.process("Resources")]),
        .target(name: "TextFilters", resources: [.process("Resources")]),
        .target(name: "Math", dependencies: ["MarkdownEngine", "Contributions"], resources: [.process("Resources")]),
        .target(
            name: "MathRendering",
            dependencies: [
                "Math",
                .product(name: "SwiftUIMath", package: "swiftui-math"),
            ]
        ),
        .target(
            name: "Diagrams",
            dependencies: ["MarkdownEngine", "Contributions", "Themes"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "DiagramRendering",
            dependencies: ["Diagrams", "DiagramWebKitPool", "Themes"],
            resources: [.process("Resources")]
        ),
        .target(name: "DiagramWebKitPool"),
        .target(
            name: "DiagramsD2",
            dependencies: ["MarkdownEngine", "Contributions", "Themes"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "D2Rendering",
            dependencies: ["DiagramsD2", "DiagramWebKitPool", "Themes"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "DiagramsGraphviz",
            dependencies: ["MarkdownEngine", "Contributions", "Themes"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "GraphvizRendering",
            dependencies: ["DiagramsGraphviz", "DiagramWebKitPool", "Themes"],
            resources: [.process("Resources")]
        ),

        .testTarget(name: "FileCoreTests", dependencies: ["FileCore"]),
        .testTarget(name: "CommandBridgeTests", dependencies: ["CommandBridge"]),
        .testTarget(name: "LocalResourceAccessTests", dependencies: ["LocalResourceAccess"]),
        .testTarget(name: "TextSearchTests", dependencies: ["TextSearch"]),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"]),
        .testTarget(name: "ThemesTests", dependencies: ["Themes"]),
        .testTarget(name: "WorkspaceTests", dependencies: ["Workspace"]),
        .testTarget(name: "FileTreeTests", dependencies: ["FileTree"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore", "JSONSupport"]),
        .testTarget(name: "HighlightingTests", dependencies: ["Highlighting"]),
        .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"]),
        .testTarget(
            name: "PreviewTests",
            dependencies: ["Preview", .product(name: "Textual", package: "textual")]
        ),
        .testTarget(name: "OutlineUITests", dependencies: ["OutlineUI", "JSONSupport"]),
        .testTarget(name: "JSONSupportTests", dependencies: ["JSONSupport"]),
        .testTarget(
            name: "ExportServiceTests",
            dependencies: ["ExportService", "MarkdownEngine", .product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .testTarget(name: "ContributionsTests", dependencies: ["Contributions", "MarkdownEngine"]),
        .testTarget(name: "TextFiltersTests", dependencies: ["TextFilters"]),
        .testTarget(name: "MathTests", dependencies: ["Math", "MarkdownEngine"]),
        .testTarget(name: "MathRenderingTests", dependencies: ["MathRendering"]),
        .testTarget(name: "DiagramsTests", dependencies: ["Diagrams", "MarkdownEngine"]),
        .testTarget(name: "DiagramRenderingTests", dependencies: ["DiagramRendering", "DiagramWebKitPool"]),
        .testTarget(name: "DiagramsD2Tests", dependencies: ["DiagramsD2", "MarkdownEngine", "Themes"]),
        .testTarget(name: "D2RenderingTests", dependencies: ["D2Rendering"]),
        .testTarget(name: "DiagramsGraphvizTests", dependencies: ["DiagramsGraphviz", "MarkdownEngine"]),
        .testTarget(name: "GraphvizRenderingTests", dependencies: ["GraphvizRendering"]),
        .testTarget(
            name: "ExportDiagramIntegrationTests",
            dependencies: [
                "ExportService", "Diagrams", "DiagramRendering",
                "DiagramsD2", "D2Rendering", "DiagramsGraphviz", "GraphvizRendering",
            ]
        ),
    ]
)
