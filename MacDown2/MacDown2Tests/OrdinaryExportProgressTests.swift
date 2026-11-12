import AppSettings
import ExportService
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes

@MainActor
struct OrdinaryExportProgressTests {
    @Test func cancellationRevokesPublicationAndKeepsThePhaseVisibleUntilCleanup() throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let identifier = ObjectIdentifier(model)
        let lease = ExportLifetimeLease()
        coordinator.setExporting(true, for: model)
        coordinator.exportLeases[identifier] = lease
        coordinator.exportTasks[identifier] = Task {}

        #expect(coordinator.exportPhase(for: model) == .choosingDestination)
        coordinator.setExportPhase(.loadingPDF, for: model)
        coordinator.cancelExport(for: model)
        #expect(coordinator.exportPhase(for: model) == .cancelling)
        #expect(throws: CancellationError.self) { try lease.withPublicationCutoff {} }
        coordinator.setExportPhase(.publishing, for: model)
        #expect(coordinator.exportPhase(for: model) == .cancelling)

        coordinator.setExporting(false, for: model)
        #expect(coordinator.exportPhase(for: model) == nil)
        #expect(coordinator.exportTasks[identifier] == nil)
        #expect(coordinator.exportLeases[identifier] == nil)
    }

    @Test func activePrintAndPublicationDoNotOfferAFalseCancelButton() {
        #expect(!ExportPhase.printingPDF.canRequestCancellation)
        #expect(!ExportPhase.publishing.canRequestCancellation)
        #expect(ExportPhase.loadingPDF.canRequestCancellation)
        #expect(ExportPhase.validatingPDF.canRequestCancellation)
    }
}
