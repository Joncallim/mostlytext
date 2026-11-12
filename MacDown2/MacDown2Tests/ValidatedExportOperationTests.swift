import AppKit
import AppSettings
import ExportService
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes
import Workspace

@MainActor
@Suite("Disabled validated export operation")
struct ValidatedExportOperationTests {
    @Test func cachedParseRejectsCanonicallyEquivalentButDifferentSourceBytes() async throws {
        let original = "caf\u{00E9}"
        let parsed = try await ParseEngine().parse(original, revision: 1)
        let cache = FrozenExportParse(text: original, revision: 1, document: parsed)
        do {
            _ = try await cache.parse("cafe\u{0301}", options: .default, revision: 1)
            Issue.record("A different UTF-8 source borrowed the frozen parse")
        } catch is ExportError {
            // Source binding is byte exact, not Swift String canonical equivalence.
        }
    }

    private struct Fixture {
        let coordinator: WindowCoordinator
        let first: WindowController
        let second: WindowController
        let folder: URL
    }

    private func fixture() throws -> Fixture {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("validated-operation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        func makeController(_ name: String) throws -> WindowController {
            let model = coordinator.makeWindowModel()
            let url = folder.appendingPathComponent(name)
            let source = "# \(name)\n\n[TOC]\n"
            try source.write(to: url, atomically: true, encoding: .utf8)
            let document = FileDocument(
                fileURL: url, text: source
            )
            model.tabStore.newTab(document: document)
            return WindowController(
                model: model, coordinator: coordinator,
                themeController: coordinator.themeController,
                grammarRegistry: coordinator.grammarRegistry,
                fileTreePreferences: preferences
            )
        }
        let first = try makeController("first.md")
        let second = try makeController("second.md")
        coordinator.controllers = [first, second]
        first.window?.animationBehavior = .none
        second.window?.animationBehavior = .none
        first.window?.makeKeyAndOrderFront(nil)
        coordinator.updateKeyModel()
        return Fixture(coordinator: coordinator, first: first, second: second, folder: folder)
    }

    @Test func panelFocusAndLaterEditsCannotRetargetTheFrozenContribution() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        let second = item.second
        let folder = item.folder
        defer {
            first.close()
            second.close()
            try? FileManager.default.removeItem(at: folder)
        }
        let targetURL = folder.appendingPathComponent("accepted.html")
        let pending = coordinator.beginValidatedSVGExport(from: first, chooseTarget: { window in
            #expect(window === first.window)
            first.model.tabStore.updateActiveDocument { $0.updatingText("# Accepted\n\n[TOC]\n") }
            coordinator.themeController.setAppearance(.dark)
            second.window?.makeKeyAndOrderFront(nil)
            coordinator.updateKeyModel()
            return .html(url: targetURL, mode: .selfContained)
        }, beforePublication: { request in
            #expect(request.text == "# Accepted\n\n[TOC]\n")
            #expect(request.theme == BundledThemes.dark)
            #expect(!request.contributions.isEmpty)
            #expect(request.contributions.allSatisfy { $0.sourceGeneration == request.sourceGeneration })
            coordinator.themeController.setAppearance(.light)
            first.model.tabStore.updateActiveDocument { $0.updatingText("# Later\n\n[TOC]\n") }
        })
        let task = try #require(pending)
        #expect(coordinator.isExporting(first.model))
        let result = try #require(try await task.value)
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        #expect(result.primaryFile == targetURL)
        #expect(html.contains(">Accepted</h1>"))
        #expect(html.contains("<li>Accepted</li>"))
        #expect(!html.contains("Later"))
        #expect(!html.contains("[TOC]"))
        #expect(html.contains(ExportThemeStylesheet.variables(for: BundledThemes.dark)))
        #expect(!html.contains(ExportThemeStylesheet.variables(for: BundledThemes.light)))
        #expect(!html.contains("second.md"))
        #expect(!coordinator.isExporting(first.model))
    }

    @Test func saveAsReplacementDuringPanelRejectsTheOldOrigin() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        let second = item.second
        let folder = item.folder
        defer {
            first.close()
            second.close()
            try? FileManager.default.removeItem(at: folder)
        }
        let targetURL = folder.appendingPathComponent("replaced.html")
        let pending = coordinator.beginValidatedSVGExport(from: first) { _ in
            first.model.tabStore.updateActiveDocument {
                $0.renamed(to: folder.appendingPathComponent("saved-as.md"))
            }
            return .html(url: targetURL, mode: .selfContained)
        }
        let task = try #require(pending)
        do {
            _ = try await task.value
            Issue.record("Replaced document exported from its old origin")
        } catch is CancellationError {
            #expect(!FileManager.default.fileExists(atPath: targetURL.path))
            #expect(!coordinator.isExporting(first.model))
        }
    }

    @Test func cancellingDuringPanelKeepsThePreviousExportAndReleasesTheGuard() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        let second = item.second
        let folder = item.folder
        defer {
            first.close()
            second.close()
            try? FileManager.default.removeItem(at: folder)
        }
        let targetURL = folder.appendingPathComponent("existing.html")
        try "previous export".write(to: targetURL, atomically: true, encoding: .utf8)
        var panelEntered = false
        let pending = coordinator.beginValidatedSVGExport(from: first) { _ in
            panelEntered = true
            try? await Task.sleep(for: .seconds(5))
            return .html(url: targetURL, mode: .selfContained)
        }
        let task = try #require(pending)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !panelEntered, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panelEntered)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled panel work published an export")
        } catch is CancellationError {
            #expect(try String(contentsOf: targetURL, encoding: .utf8) == "previous export")
            #expect(!coordinator.isExporting(first.model))
        }
    }

    @Test func cancellationAfterContributionsKeepsThePreviousExport() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        let second = item.second
        let folder = item.folder
        defer {
            first.close()
            second.close()
            try? FileManager.default.removeItem(at: folder)
        }
        let targetURL = folder.appendingPathComponent("existing.html")
        try "previous export".write(to: targetURL, atomically: true, encoding: .utf8)
        let pending = coordinator.beginValidatedSVGExport(from: first, chooseTarget: { _ in
            .html(url: targetURL, mode: .selfContained)
        }, beforePublication: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let task = try #require(pending)
        do {
            _ = try await task.value
            Issue.record("Cancelled contribution work replaced the previous export")
        } catch is CancellationError {
            #expect(try String(contentsOf: targetURL, encoding: .utf8) == "previous export")
            #expect(!coordinator.isExporting(first.model))
        }
    }

    @Test func realSaveSheetRemainsOnTheCapturedWindowWhenFocusMoves() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        defer {
            first.close()
            item.second.close()
            try? FileManager.default.removeItem(at: item.folder)
        }
        var attachedToOrigin = false
        let pending = coordinator.beginValidatedSVGExportUsingPanel(from: first) { panel in
            attachedToOrigin = panel.sheetParent === first.window
            item.second.window?.makeKeyAndOrderFront(nil)
            coordinator.updateKeyModel()
            #expect(panel.sheetParent === first.window)
            panel.cancel(nil)
        }
        let task = try #require(pending)
        let result = try await task.value
        #expect(attachedToOrigin)
        #expect(result == nil)
        #expect(!coordinator.isExporting(first.model))
    }

    @Test func originCloseNotificationSettlesTheRealSheetWithoutAnExport() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        defer {
            first.close()
            item.second.close()
            try? FileManager.default.removeItem(at: item.folder)
        }
        let pending = coordinator.beginValidatedSVGExportUsingPanel(from: first) { _ in
            guard let window = first.window else { return }
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        }
        let task = try #require(pending)
        let result = try await task.value
        #expect(result == nil)
        #expect(!coordinator.isExporting(first.model))
    }

    @Test func closeAfterContributionWorkRevokesPublication() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        let second = item.second
        let folder = item.folder
        defer {
            first.close()
            second.close()
            try? FileManager.default.removeItem(at: folder)
        }
        let targetURL = folder.appendingPathComponent("closed.html")
        let pending = coordinator.beginValidatedSVGExport(from: first, chooseTarget: { _ in
            .html(url: targetURL, mode: .selfContained)
        }, beforePublication: { _ in
            await Task.yield()
            first.close()
        })
        let task = try #require(pending)
        do {
            _ = try await task.value
            Issue.record("Closed window published a validated export")
        } catch is CancellationError {
            #expect(!FileManager.default.fileExists(atPath: targetURL.path))
            #expect(!coordinator.isExporting(first.model))
        }
    }
}

extension ValidatedExportOperationTests {
    @Test func closeBeforeTaskStartsNeverPresentsTheSheet() async throws {
        let item = try fixture()
        let coordinator = item.coordinator
        let first = item.first
        defer {
            first.close()
            item.second.close()
            try? FileManager.default.removeItem(at: item.folder)
        }
        var presented = false
        let pending = coordinator.beginValidatedSVGExportUsingPanel(from: first) { panel in
            presented = true
            panel.cancel(nil)
        }
        let task = try #require(pending)
        #expect(coordinator.isExporting(first.model))
        first.close()
        do {
            _ = try await task.value
            Issue.record("A closed origin reached the export sheet")
        } catch is CancellationError {
            #expect(!presented)
            #expect(!coordinator.isExporting(first.model))
        }
    }
}
