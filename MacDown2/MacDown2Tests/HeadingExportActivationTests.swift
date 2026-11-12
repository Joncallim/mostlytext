import Contributions
import ExportService
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

@MainActor
struct HeadingExportActivationTests {
    private actor CountingParser: ParseExecuting {
        var count = 0
        var parseMilliseconds: [Double] = []
        let parser = ParseEngine()

        func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
            count += 1
            let start = ContinuousClock.now
            let result = try await parser.parse(text, options: options, revision: revision)
            let elapsed = start.duration(to: .now).components
            parseMilliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            return result
        }
    }

    @Test func theProductionExporterRegistersLinkedTOCsAndUsesOneFrozenParse() async throws {
        let source = "[TOC]\n\n# A\n\n# A\n\n# A-1\n"
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        defer { MathPreviewLiveSourceTests.dispose(fixture) }
        let directory = try TextFilterCoordinatorTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try #require(fixture.controller.model.activeDocument)
        let snapshot = await OrdinaryExportSnapshot(
            document: document,
            theme: BundledThemes.light,
            parseOptions: .default
        )
        let exporter = ExportCoordinator(
            coordinator: fixture.coordinator, themeController: fixture.coordinator.themeController,
            appSettings: fixture.coordinator.appSettings
        )
        let parser = CountingParser()
        let output = try await exporter.performExport(
            snapshot: snapshot, selection: .init(url: directory.appendingPathComponent("result.html"),
                                                 format: .standaloneHTML, style: .embedded), engine: parser
        )
        let html = try String(contentsOf: output.primaryFile, encoding: .utf8)
        #expect(await parser.count == 1)
        for fragment in ["a", "a-1", "a-1-1"] {
            #expect(html.contains("href=\"#\(fragment)\""))
            #expect(html.contains("<h1 id=\"\(fragment)\">"))
        }
        #expect(!html.contains("[TOC]") && !html.contains("<!--MT117-"))
        #expect(fixture.controller.model.activeDocument?.text.utf8.elementsEqual(source.utf8) == true)
        #expect(snapshot.documentID == document.id && snapshot.recoveryEpoch == document.recoveryEpoch)
    }

    @Test func failedRequestedTOCPreparationPreservesPriorPrimaryAndCompanionOutput() async throws {
        let source = "<div title='unterminated>\n\n[TOC]\n\n# Target\n"
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        defer { MathPreviewLiveSourceTests.dispose(fixture) }
        let parsed = try await ParseEngine().parse(source, revision: 1)
        try #require(TOCContribution.containsMarker(in: source, document: parsed))
        let directory = try TextFilterCoordinatorTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("result.html")
        let companion = directory.appendingPathComponent("result.assets/keep.txt")
        try FileManager.default.createDirectory(
            at: companion.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("previous primary".utf8).write(to: primary)
        try Data("previous companion".utf8).write(to: companion)
        let exporter = ExportCoordinator(
            coordinator: fixture.coordinator, themeController: fixture.coordinator.themeController,
            appSettings: fixture.coordinator.appSettings
        )
        let snapshot = try await OrdinaryExportSnapshot(document: #require(fixture.controller.model.activeDocument),
                                                        theme: BundledThemes.light, parseOptions: .default)
        let error = await #expect(throws: ExportError.self) {
            _ = try await exporter.performExport(snapshot: snapshot, selection: .init(
                url: primary, format: .standaloneHTML, style: .embedded
            ))
        }
        guard case .headingNavigationUnavailable = error else {
            Issue.record("Requested navigation must fail before publication")
            return
        }
        #expect(try Data(contentsOf: primary) == Data("previous primary".utf8))
        #expect(try Data(contentsOf: companion) == Data("previous companion".utf8))
    }

    @Test func aCodeMarkerDoesNotActivateTheHeadingDOMGateForOrdinaryHTML() async throws {
        let source = "<div title='unterminated>\n\n```\n[TOC]\n```\n\n# Target\n"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        try #require(!TOCContribution.containsMarker(in: source, document: parsed))
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        defer { MathPreviewLiveSourceTests.dispose(fixture) }
        let directory = try TextFilterCoordinatorTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = ExportCoordinator(
            coordinator: fixture.coordinator, themeController: fixture.coordinator.themeController,
            appSettings: fixture.coordinator.appSettings
        )
        let snapshot = try await OrdinaryExportSnapshot(document: #require(fixture.controller.model.activeDocument),
                                                        theme: BundledThemes.light, parseOptions: .default)
        let output = try await exporter.performExport(snapshot: snapshot, selection: .init(
            url: directory.appendingPathComponent("result.html"), format: .standaloneHTML, style: .embedded
        ))
        let html = try String(contentsOf: output.primaryFile, encoding: .utf8)
        #expect(html.contains("<h1>Target</h1>") && !html.contains("<h1 id="))
        #expect(html.contains("<div title='unterminated>"))
    }
}

extension HeadingExportActivationTests {
    @Test func productionLinkedExportRecordsOneMiBAndDuplicateHeadingPhaseMeasurements() async throws {
        let paragraph = String(repeating: "Ordinary source text. ", count: 50) + "\n\n"
        let source = "[TOC]\n\n" + String(repeating: paragraph, count: 1000) +
            String(repeating: "# Duplicate\n\n", count: 4096)
        try #require(source.utf8.count >= 1024 * 1024)
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        defer { MathPreviewLiveSourceTests.dispose(fixture) }
        let directory = try TextFilterCoordinatorTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try await OrdinaryExportSnapshot(document: #require(fixture.controller.model.activeDocument),
                                                        theme: BundledThemes.light, parseOptions: .default)
        let exporter = ExportCoordinator(
            coordinator: fixture.coordinator, themeController: fixture.coordinator.themeController,
            appSettings: fixture.coordinator.appSettings
        )
        let parser = CountingParser()
        var totals: [Double] = []
        for sample in 0 ..< 3 {
            let start = ContinuousClock.now
            let output = try await exporter.performExport(snapshot: snapshot, selection: .init(
                url: directory.appendingPathComponent("measurement-\(sample).html"),
                format: .standaloneHTML, style: .embedded
            ), engine: parser)
            let elapsed = start.duration(to: .now).components
            totals.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            let html = try String(contentsOf: output.primaryFile, encoding: .utf8)
            #expect(html.components(separatedBy: "<h1 id=").count - 1 == 4096)
            #expect(html.contains("href=\"#duplicate-4095\"") && html.contains("id=\"duplicate-4095\""))
            #expect(!output.diagnostics.contains { $0.severity == .error })
        }
        #expect(await parser.count == 3, "Every complete production export must use exactly one frozen parse")
        let parse = await parser.parseMilliseconds
        #if DEBUG
            let configuration = "Debug"
        #else
            let configuration = "Release"
        #endif
        print("TOC-PHASE configuration=\(configuration) source_bytes=\(source.utf8.count) headings=4096")
        print("TOC-PHASE parse_ms=\(parse) complete_production_export_ms=\(totals)")
        // These are complete command-body timings, including file publication;
        // they do not measure save-panel interaction, UI latency or peak RSS.
    }
}
