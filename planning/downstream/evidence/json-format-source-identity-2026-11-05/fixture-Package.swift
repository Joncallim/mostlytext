// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedJSONSourceFixture", platforms: [.macOS(.v26)], targets: [
    .target(name: "JSONSupport", resources: [.process("Resources")]),
    .testTarget(name: "JSONSupportTests", dependencies: ["JSONSupport"]),
])
