// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OwnedDiagramSourceFixture", platforms: [.macOS(.v26)],
    dependencies: [.package(path: "Dependencies/swift-markdown"), .package(path: "Dependencies/yams")],
    targets: [
        .target(name: "MarkdownEngine", dependencies: [.product(name: "Markdown", package: "swift-markdown"), .product(name: "Yams", package: "yams")]),
        .target(name: "Diagrams", dependencies: ["MarkdownEngine"]),
        .target(name: "DiagramsD2", dependencies: ["MarkdownEngine"]),
        .target(name: "DiagramsGraphviz", dependencies: ["MarkdownEngine"]),
        .testTarget(name: "ScannerTests", dependencies: ["MarkdownEngine", "Diagrams", "DiagramsD2", "DiagramsGraphviz"]),
    ])
