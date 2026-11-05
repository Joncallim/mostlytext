// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OwnedMathParserSource", platforms: [.macOS("26.0")], targets: [
 .target(name: "SwiftUIMath"), .testTarget(name: "SwiftUIMathTests", dependencies: ["SwiftUIMath"]),
])
