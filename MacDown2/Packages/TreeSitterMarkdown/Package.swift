// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TreeSitterMarkdown",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "TreeSitterMarkdown",
            targets: [
                "TreeSitterMarkdown",
                "TreeSitterMarkdownInline",
                "TreeSitterMarkdownResources",
                "TreeSitterMarkdownInlineResources",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Joncallim/SwiftTreeSitter",
            revision: "7d2dc87e8b9326062d75bc1ef985f17d28e94da9"
        ),
    ],
    targets: [
        .target(
            name: "TreeSitterMarkdown",
            dependencies: [],
            path: "Sources/TreeSitterMarkdown",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterMarkdownInline",
            dependencies: [],
            path: "Sources/TreeSitterMarkdownInline",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterMarkdownResources",
            dependencies: ["TreeSitterMarkdown"],
            path: "Sources/TreeSitterMarkdownResources",
            resources: [.copy("queries")]
        ),
        .target(
            name: "TreeSitterMarkdownInlineResources",
            dependencies: ["TreeSitterMarkdownInline"],
            path: "Sources/TreeSitterMarkdownInlineResources",
            resources: [.copy("queries")]
        ),
    ],
    cLanguageStandard: .c11
)
