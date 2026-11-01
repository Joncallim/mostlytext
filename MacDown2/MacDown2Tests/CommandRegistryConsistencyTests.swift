import Foundation
@testable import MacDown2
import Testing

/// Issue #117 item 4 — the command palette's hand-maintained list cannot
/// silently drift from the menu commands.
@MainActor
@Suite("CommandRegistryConsistency")
struct CommandRegistryConsistencyTests {
    private static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MacDown2")

    /// Literal first arguments of `Button`, `Menu` and `CommandMenu` in every
    /// `Commands` source. Titles supplied by a label closure or a variable
    /// (the Layout choices, theme names, text-filter names) are invisible to
    /// this scan; they sit inside menus that are catalogued as containers.
    private static func sourceMenuTitles() throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path)
            .filter { $0.hasSuffix(".swift") }
        let pattern = try Regex(#"\b(?:Button|Menu|CommandMenu)\("((?:[^"\\]|\\.)*)""#)
        let declaration = try Regex(#"\b(?:struct|class)\s+\w+\s*:\s*[^\{]*\bCommands\b"#)
        var titles: Set<String> = []
        for file in files {
            let text = try String(contentsOf: sourceDirectory.appendingPathComponent(file), encoding: .utf8)
            guard file.hasPrefix("WorkspaceCommands") || text.firstMatch(of: declaration) != nil else { continue }
            // The catalog describes shipped commands. The native acceptance
            // menu exists only in a separately flagged test build.
            var acceptanceBlockDepth = 0
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "#if ISSUE117_NATIVE_ACCEPTANCE" {
                    acceptanceBlockDepth += 1
                    continue
                }
                if acceptanceBlockDepth > 0 {
                    if trimmed.hasPrefix("#if ") {
                        acceptanceBlockDepth += 1
                    } else if trimmed == "#endif" {
                        acceptanceBlockDepth -= 1
                    }
                    continue
                }
                if trimmed.hasPrefix("//") {
                    continue
                }
                for match in line.matches(of: pattern) {
                    if let title = match.output[1].substring {
                        titles.insert(String(title))
                    }
                }
            }
        }
        return titles
    }

    private static var paletteEntries: [(id: String, title: String)] {
        AppPaletteCommand.standard.map { ($0.id, $0.title) }
    }

    private func validate(
        catalog: [CommandDescriptor] = CommandDescriptor.catalog,
        palette: [(id: String, title: String)] = CommandRegistryConsistencyTests.paletteEntries,
        titles: Set<String>? = nil
    ) throws -> CommandRegistryConsistency.Report {
        try CommandRegistryConsistency.validate(
            catalog: catalog,
            paletteEntries: palette,
            sourceMenuTitles: titles ?? Self.sourceMenuTitles()
        )
    }

    @Test func sourceScanFindsTheMenuCommands() throws {
        let titles = try Self.sourceMenuTitles()
        #expect(titles.count > 40, "scan found only \(titles.count) titles; the source location is probably wrong")
        #expect(titles.contains("Save As…"))
        #expect(titles.contains("Sort Lines"))
        #expect(titles.contains("Find…"))
        #expect(titles.contains("About MostlyText"))
        #expect(titles.contains("Open Source Licenses…"))
        #expect(!titles.contains("Validate Export… (#117 Test Build)"))
        #expect(!titles.contains("Show #117 Acceptance Log"))
    }

    @Test func shippedCatalogIsConsistentWithMenuAndPalette() throws {
        let report = try validate()
        #expect(report.isConsistent, Comment(rawValue: report.issues.joined(separator: "; ")))
    }

    @Test func aNewMenuItemWithoutACatalogEntryIsReported() throws {
        let titles = try Self.sourceMenuTitles().union(["Brand New Command"])
        let report = try validate(titles: titles)
        #expect(report.issues == ["menu item 'Brand New Command' has no catalog entry"])
    }

    @Test func aRenamedOrRemovedMenuItemLeavesAStaleCatalogEntry() throws {
        let titles = try Self.sourceMenuTitles().subtracting(["Sort Lines"])
        let report = try validate(titles: titles)
        #expect(report.issues == ["catalog entry 'Sort Lines' matches no menu item in the Commands sources"])
    }

    @Test func aPaletteEntryWithoutACatalogRecordIsReported() throws {
        let palette = Self.paletteEntries + [(id: "rogue", title: "Rogue")]
        let report = try validate(palette: palette)
        #expect(report.issues == ["palette entry 'rogue' has no catalog record"])
    }

    @Test func aPaletteEligibleCatalogEntryWithoutAPaletteCommandIsReported() throws {
        let palette = Self.paletteEntries.filter { $0.id != "save" }
        let report = try validate(palette: palette)
        #expect(report.issues == ["catalog marks 'Save' palette-eligible as 'save' but the palette has no such entry"])
    }

    @Test func aPaletteTitleThatDriftsFromItsMenuItemIsReported() throws {
        let palette = Self.paletteEntries.map { $0.id == "saveAs" ? (id: $0.id, title: "Save As") : $0 }
        let report = try validate(palette: palette)
        #expect(report.issues == ["palette entry 'saveAs' is titled 'Save As' but its menu item is 'Save As…'"])
    }

    @Test func duplicateCatalogTitlesAndPaletteIDsAreReported() throws {
        let catalog = CommandDescriptor.catalog + [CommandDescriptor("Bold", .excluded(.notYetWired))]
        #expect(try validate(catalog: catalog).issues == ["catalog lists 'Bold' more than once"])
        let palette = Self.paletteEntries + [Self.paletteEntries[0]]
        #expect(try validate(palette: palette).issues == ["palette lists id 'newFile' more than once"])
    }
}
