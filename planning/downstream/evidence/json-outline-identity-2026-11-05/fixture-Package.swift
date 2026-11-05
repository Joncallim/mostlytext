// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedOutlineSourceFixture", platforms: [.macOS(.v26)],
 dependencies: [.package(path: "Dependencies/swift-markdown"), .package(path: "Dependencies/yams")], targets: [
 .target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"), .product(name: "Yams", package: "yams")]),
 .target(name: "JSONSupport", resources: [.process("Resources")]),
 .target(name: "OutlineUI", dependencies: ["MarkdownEngine", "JSONSupport"]),
 .testTarget(name: "ModelTests", dependencies: ["JSONSupport", "OutlineUI", "MarkdownEngine"]),
])
