// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ReplacementPlanBoundsProbe", platforms: [.macOS(.v26)], targets: [
    .target(name: "JSONSupport", resources: [.process("Resources")]),
    .target(name: "FileCore", dependencies: ["JSONSupport"], resources: [.process("Resources")]),
    .target(name: "TextSearch", dependencies: ["FileCore"], resources: [.process("Resources")]),
    .testTarget(name: "TextSearchTests", dependencies: ["TextSearch"])
])
