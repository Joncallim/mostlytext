// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedSharedMathAnalysis", platforms: [.macOS(.v26)], dependencies: [
 .package(url: "https://github.com/Joncallim/swift-markdown", revision: "abfafeccd6f0434daf1a667b92d227adb83b50c8"),
 .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
 .package(path: "/Volumes/Fast SSD/CORTANA-GitHub/worktrees/github/mostlytext-shared-math-analysis/MacDown2/Packages/MathSyntax"),
], targets: [.target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"),
 .product(name: "Yams", package: "Yams")]), .target(name: "Contributions", dependencies: ["MarkdownEngine"], resources: [.process("Resources")]),
 .target(name: "Math", dependencies: ["MarkdownEngine", "Contributions", .product(name: "MathSyntax", package: "MathSyntax")], resources: [.process("Resources")]),
 .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"]),
 .testTarget(name: "MathTests", dependencies: ["Math", "MarkdownEngine"]),])
