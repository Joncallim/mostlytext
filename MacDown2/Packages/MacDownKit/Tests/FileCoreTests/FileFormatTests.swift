@testable import FileCore
import Foundation
import Testing
import UniformTypeIdentifiers

@Test func registryIncludesMarkdown() {
    let registry = FileFormatRegistry()
    let format = registry.formats.first { $0.id == "markdown" }
    #expect(format != nil)
    #expect(format?.extensions.contains("md") == true)
    #expect(format?.previewCapability == .markdown)
    #expect(format?.defaultPreviewMode == .rendered)
    #expect(format?.utType == UTType(filenameExtension: "md"))
}

@Test func registryIncludesHTMLAndJSON() {
    let registry = FileFormatRegistry()
    #expect(registry.formats.first { $0.id == "html" }?.previewCapability == .htmlSourceAndRendered)
    #expect(registry.formats.first { $0.id == "html" }?.supportedPreviewModes == [.source, .rendered])
    #expect(registry.formats.first { $0.id == "json" }?.previewCapability == .jsonOutline)
    #expect(registry.formats.first { $0.id == "json" }?.defaultPreviewMode == .outline)
}

@Test func sourceOnlyFormatsDeclareNoCapability() {
    let registry = FileFormatRegistry()
    for format in registry.formats where !["markdown", "html", "json"].contains(format.id) {
        #expect(format.previewCapability == .none, "\(format.id) must not inherit a renderer")
        #expect(format.defaultPreviewMode == nil)
        #expect(format.supportedPreviewModes.isEmpty)
    }
}

@Test func formatForURLUsesPathExtension() {
    let registry = FileFormatRegistry()
    let mdURL = URL(fileURLWithPath: "/tmp/readme.md")
    let format = FileFormat.format(for: mdURL, in: registry)
    #expect(format?.id == "markdown")
}

@Test func formatForUnknownExtensionFallsBackToNil() {
    let registry = FileFormatRegistry()
    let unknownURL = URL(fileURLWithPath: "/tmp/archive.unknown")
    #expect(FileFormat.format(for: unknownURL, in: registry) == nil)
}

@Test func allRegisteredExtensionsAreLowercased() {
    let registry = FileFormatRegistry()
    for format in registry.formats {
        for ext in format.extensions {
            #expect(ext == ext.lowercased(), "Extension '\(ext)' for \(format.id) must be lowercased")
        }
    }
}

@Test func everyFormatHasAName() {
    let registry = FileFormatRegistry()
    for format in registry.formats {
        #expect(!format.name.isEmpty)
    }
}

@Test func plainTextDisplayNameUsesTheCompiledFileCoreCatalog() throws {
    // Standalone SwiftPM copies XCStrings as source; Xcode compiles it for the
    // app. Compile the actual package catalog before checking runtime lookup.
    let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FileCore/Resources/Localizable.xcstrings")
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("mostlytext-filecore-catalog-\(UUID().uuidString)", isDirectory: true)
    let bundleURL = scratch.appendingPathComponent("FileCoreProof.bundle", isDirectory: true)
    let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["xcstringstool", "compile", catalog.path, "--output-directory", resources.path]
    let diagnostics = Pipe()
    compiler.standardError = diagnostics
    try compiler.run()
    compiler.waitUntilExit()
    let compilerError = String(data: diagnostics.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "unreadable compiler diagnostics"
    #expect(compiler.terminationStatus == 0, "XCStrings compiler failed: \(compilerError)")

    let frenchStrings = resources.appendingPathComponent("fr.lproj/Localizable.strings")
    #expect(FileManager.default.fileExists(atPath: frenchStrings.path))
    let frenchBundle = try #require(Bundle(url: resources.appendingPathComponent("fr.lproj")))
    #expect(String(localized: "Plain Text", bundle: frenchBundle) == "Texte brut")
    #expect(FileFormatRegistry.plainTextDisplayName(bundle: frenchBundle) == "Texte brut")
    let registered = try #require(FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" })
    #expect(registered.name == FileFormatRegistry.plainTextDisplayName())
    #expect(registered.extensions == ["txt"])
    #expect(registered.utType == .plainText)

    let fallback = FileDocument.format(for: URL(fileURLWithPath: "/tmp/unknown-extension.unknown"))
    #expect(fallback.id == registered.id)
    #expect(fallback.name == registered.name)
}

@Test func texAndLatexExtensionsResolveToTheSourceOnlyTeXFormat() {
    let registry = FileFormatRegistry()
    for name in ["paper.tex", "paper.latex", "PAPER.TEX"] {
        let format = FileFormat.format(for: URL(fileURLWithPath: "/tmp/\(name)"), in: registry)
        #expect(format?.id == "tex", "\(name)")
        #expect(format?.previewCapability == PreviewCapability.none)
    }
}
