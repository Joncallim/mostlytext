// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LegacyMathGrammarBaseline", platforms: [.macOS(.v26)], targets: [.target(name: "LegacyMath"), .testTarget(name: "LegacyMathTests", dependencies: ["LegacyMath"])])
