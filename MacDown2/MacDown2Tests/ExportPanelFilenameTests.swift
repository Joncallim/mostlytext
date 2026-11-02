import AppKit
@testable import MacDown2
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite("Ordinary export panel filename")
struct ExportPanelFilenameTests {
    private final class FilenameFields: ExportFilenamePanel {
        var nameFieldStringValue = "Untitled"
        var allowedContentTypes: [UTType] = [.plainText]
    }

    @Test(arguments: ["Untitled", "Untitled.html"])
    func initialFilenameReplacesTheSystemDefault(_ systemDefault: String) {
        let panel = FilenameFields()
        panel.nameFieldStringValue = systemDefault

        ExportCoordinator.initializeFilename(.standaloneHTML, in: panel, defaultBaseName: "origin-A")

        #expect(panel.nameFieldStringValue == "origin-A.html")
        #expect(panel.allowedContentTypes == [.html])
    }

    @Test func formatChangesPreserveTheUserEnteredBasename() {
        let panel = FilenameFields()
        ExportCoordinator.initializeFilename(.standaloneHTML, in: panel, defaultBaseName: "origin-A")
        panel.nameFieldStringValue = "Report v1.2.html"

        ExportCoordinator.apply(.pdf, to: panel, defaultBaseName: "origin-A")
        #expect(panel.nameFieldStringValue == "Report v1.2.pdf")
        #expect(panel.allowedContentTypes == [.pdf])

        ExportCoordinator.apply(.standaloneHTML, to: panel, defaultBaseName: "origin-A")
        #expect(panel.nameFieldStringValue == "Report v1.2.html")
        #expect(panel.allowedContentTypes == [.html])
    }
}
