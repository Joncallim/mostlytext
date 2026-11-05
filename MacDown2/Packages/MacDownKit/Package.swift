// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacDownKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FileCore", targets: ["FileCore"]),
        .library(name: "CommandBridge", targets: ["CommandBridge"]),
        .library(name: "CommandLineSupport", targets: ["CommandLineSupport"]),
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
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(
            url: "https://github.com/Joncallim/SwiftTreeSitter",
            revision: "0beea992c4246f93a122de846c8611c9be19aeb7"
        ),
        .package(url: "https://github.com/Joncallim/Neon", revision: "cd14f22ae8f8402b175a0bafd87560b78c7549e9"),
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
        .package(path: "../MathSyntax"),
        .package(
            url: "https://github.com/Joncallim/swift-markdown",
            revision: "abfafeccd6f0434daf1a667b92d227adb83b50c8"
        ),
        .package(url: "https://github.com/Joncallim/swift-cmark", revision: "2a5339b89b219584c8fa6c6fd378d3898eed5d57"),
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.13.9"),
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
        .package(url: "https://github.com/Joncallim/textual", revision: "c52cb5834c4695109aad2cb66294eafbc8f264c8"),
        // Match Textual's immutable engine owner/revision, so Preview and Export
        // share one parser, comment correction and structured body-inspection API.
        .package(
            url: "https://github.com/Joncallim/swiftui-math",
            revision: "2a89c2b41482988711909572d116374e47a52164"
        ),
    ],
    targets: [
        .target(name: "FileCore", dependencies: ["JSONSupport"], resources: [.process("Resources")]),
        .target(name: "CommandBridge", dependencies: ["JSONSupport"]),
        .target(name: "CommandLineSupport", dependencies: [
            "CommandBridge", .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ], resources: [.process("Resources")]),
        .target(name: "LocalResourceAccess"),
        .target(name: "TextSearch", dependencies: ["FileCore"], resources: [.process("Resources")]),
        .target(name: "AppSettings", dependencies: ["JSONSupport"]),
        .target(name: "Themes", resources: [.process("Themes")]),
        .target(name: "Workspace", dependencies: ["FileCore", "JSONSupport"], resources: [.process("Resources")]),
        .target(name: "FileTree", dependencies: ["FileCore", "JSONSupport"], resources: [.process("Resources")]),
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
                "LocalResourceAccess",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "Contributions", dependencies: ["MarkdownEngine"], resources: [.process("Resources")]),
        .target(name: "TextFilters", resources: [.process("Resources")]),
        .target(
            name: "Math",
            dependencies: ["MarkdownEngine", "Contributions", .product(name: "MathSyntax", package: "MathSyntax")],
            resources: [.process("Resources")]
        ),
        .target(
            name: "MathRendering",
            dependencies: [
                "Math", "MarkdownEngine", .product(name: "MathSyntax", package: "MathSyntax"),
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
        .testTarget(name: "CommandLineSupportTests", dependencies: ["CommandLineSupport", "CommandBridge"]),
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
            dependencies: [
                "ExportService", "MarkdownEngine", "LocalResourceAccess",
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(name: "ContributionsTests", dependencies: ["Contributions", "MarkdownEngine"]),
        .testTarget(name: "TextFiltersTests", dependencies: ["TextFilters"]),
        .testTarget(name: "MathTests", dependencies: ["Math", "MarkdownEngine"]),
        .testTarget(
            name: "MathRenderingTests",
            dependencies: [
                "MathRendering", "Math", "MarkdownEngine", .product(name: "MathSyntax", package: "MathSyntax"),
                .product(name: "SwiftUIMath", package: "swiftui-math"),
                .product(name: "Textual", package: "textual"),
            ]
        ),
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
