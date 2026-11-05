// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedMarkdownLayerFixture", platforms: [.macOS(.v26)], dependencies: [
 .package(name: "SwiftTreeSitter", path: "/Volumes/Fast SSD/CORTANA-GitHub/SwiftTreeSitter-included-ranges"),
], targets: [
 .target(name: "TreeSitterMarkdown", sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift", cSettings: [.headerSearchPath("src")]),
 .target(name: "TreeSitterMarkdownInline", sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift", cSettings: [.headerSearchPath("src")]),
 .target(name: "TreeSitterMarkdownResources", dependencies: ["TreeSitterMarkdown"], resources: [.copy("queries")]),
 .target(name: "TreeSitterMarkdownInlineResources", dependencies: ["TreeSitterMarkdownInline"], resources: [.copy("queries")]),
 .testTarget(name: "ModelTests", dependencies: ["TreeSitterMarkdown", "TreeSitterMarkdownInline", "TreeSitterMarkdownResources", "TreeSitterMarkdownInlineResources", .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"), .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
], cLanguageStandard: .c11)
