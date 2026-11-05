// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedSharedMathEvaluation", platforms: [.macOS(.v26)], dependencies: [
 .package(url: "https://github.com/Joncallim/swift-markdown", revision: "abfafeccd6f0434daf1a667b92d227adb83b50c8"),
 .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
 .package(path: "__REPO__/MacDown2/Packages/MathSyntax"),
], targets: [
 .target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"), .product(name: "Yams", package: "Yams")]),
 .target(name: "Contributions", dependencies: ["MarkdownEngine"], resources: [.process("Resources")]),
 .target(name: "Math", dependencies: ["MarkdownEngine", "Contributions", .product(name: "MathSyntax", package: "MathSyntax")], resources: [.process("Resources")]),
 .target(name: "SwiftUIMath"),
 .target(name: "MathRendering", dependencies: ["Math", "MarkdownEngine", "SwiftUIMath", .product(name: "MathSyntax", package: "MathSyntax")]),
 .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"]),
 .testTarget(name: "MathTests", dependencies: ["Math", "MarkdownEngine"]),
 .testTarget(name: "SwiftUIMathTests", dependencies: ["SwiftUIMath"]),
 .testTarget(name: "MathRenderingTests", dependencies: ["MathRendering", "Math", "MarkdownEngine", "SwiftUIMath", .product(name: "MathSyntax", package: "MathSyntax")])
])
