// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SourceObservationFixture", platforms: [.macOS("26.0")], targets: [.target(name: "MacDown2"), .testTarget(name: "MacDown2Tests", dependencies: ["MacDown2"])])
