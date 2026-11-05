// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "NativeMathAccessibilityProbe",
  platforms: [.macOS("26.0")],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", revision: "5fa253428866f2360c3754e88537f700ed2656b5"),
    .package(url: "https://github.com/Joncallim/swiftui-math", revision: "2a89c2b41482988711909572d116374e47a52164"),
    .package(url: "https://github.com/Joncallim/textual", revision: "c52cb5834c4695109aad2cb66294eafbc8f264c8")
  ],
  targets: [
  .target(name: "Preview", dependencies: [.product(name: "Textual", package: "textual")]),
  .target(name: "Math"),
  .target(name: "MathSyntax"),
  .target(name: "MathRendering", dependencies: ["Math", "MathSyntax", .product(name: "SwiftUIMath", package: "swiftui-math")]),
  .testTarget(name: "NativeMathAccessibilityProbe", dependencies: [
    "Preview", "Math", "MathSyntax", "MathRendering", .product(name: "Textual", package: "textual"),
    .product(name: "SwiftUIMath", package: "swiftui-math"),
    .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
  ])]
)
