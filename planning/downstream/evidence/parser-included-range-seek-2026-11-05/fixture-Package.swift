// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OwnedNeonClientFixture", platforms: [.macOS("26.0")], dependencies: [
 .package(name: "SwiftTreeSitter", path: "/Volumes/Fast SSD/CORTANA-GitHub/SwiftTreeSitter-range-lookup"),
], targets: [
 .target(name: "Rearrange", swiftSettings: [.swiftLanguageMode(.v5), .enableExperimentalFeature("StrictConcurrency")]),
 .target(name: "RangeState", dependencies: ["Rearrange"]),
 .target(name: "TreeSitterClient", dependencies: ["RangeState", "Rearrange", .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"), .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
 .target(name: "TreeSitterMarkdown", sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift", cSettings: [.headerSearchPath("src")]),
 .target(name: "TreeSitterMarkdownInline", sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift", cSettings: [.headerSearchPath("src")]),
 .target(name: "TreeSitterMarkdownResources", dependencies: ["TreeSitterMarkdown"], resources: [.copy("queries")]),
 .target(name: "TreeSitterMarkdownInlineResources", dependencies: ["TreeSitterMarkdownInline"], resources: [.copy("queries")]),
 .target(name: "NeonTestsTreeSitterSwift", sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift", cSettings: [.headerSearchPath("src")]),
 .target(name: "OwnedStylingCore", dependencies: ["RangeState", "TreeSitterClient", .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"), .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
 .testTarget(name: "ModelTests", dependencies: ["OwnedStylingCore", "NeonTestsTreeSitterSwift", "Rearrange", "RangeState", "TreeSitterClient", "TreeSitterMarkdown", "TreeSitterMarkdownInline", "TreeSitterMarkdownResources", "TreeSitterMarkdownInlineResources", .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"), .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
], cLanguageStandard: .c11)
