// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedMarkdownSourceFacts", platforms: [.macOS(.v26)], dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0"),
    .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
], targets: [.target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"),
    .product(name: "Yams", package: "Yams")]), .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"])])
