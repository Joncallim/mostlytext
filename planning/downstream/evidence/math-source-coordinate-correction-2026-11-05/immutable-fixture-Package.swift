// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ImmutableOwnedMarkdownSourceFacts", platforms: [.macOS(.v26)], dependencies: [
 .package(url: "https://github.com/Joncallim/swift-markdown", revision: "abfafeccd6f0434daf1a667b92d227adb83b50c8"),
 .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
], targets: [.target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"),
 .product(name: "Yams", package: "Yams")]), .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"])])
