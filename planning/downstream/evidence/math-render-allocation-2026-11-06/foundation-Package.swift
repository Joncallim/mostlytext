// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MathRasterAdmissionQualification", platforms: [.macOS("26.0")], targets: [
 .target(name: "Math"), .testTarget(name: "MathTests", dependencies: ["Math"])
])
