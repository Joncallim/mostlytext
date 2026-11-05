// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PreviewInputQualification", platforms: [.macOS("26.0")], targets: [
 .target(name: "Preview"), .testTarget(name: "PreviewTests", dependencies: ["Preview"])
])
