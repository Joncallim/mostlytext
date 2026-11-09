import AppSettings
import FileCore
import FileTree
import Foundation
import Testing

@Suite("Migration bookmark retention and future state admission")
@MainActor
struct InstallationBookmarkTests {
    private final class Preferences: FileTreePreferenceStoring {
        var filter = FileTreeFilter()
        var opensOnSingleClick = false
        var recentRootBookmarks: [Data] = []
        var recentFileBookmarks: [Data] = []
    }

    @Test func unresolvedStructuredAndOpaqueBookmarksSurviveLoadingAndRefusal() throws {
        let stored = Preferences()
        let lexical = URL(fileURLWithPath: "/private/mostlytext-unavailable-\(UUID().uuidString)")
        let record = try JSONSerialization.data(withJSONObject: [
            "bookmark": Data([0, 1, 2]).base64EncodedString(),
            "lexicalURL": lexical.absoluteString,
        ])
        let opaque = Data([255, 254, 0, 1])
        stored.recentRootBookmarks = [record, opaque]
        stored.recentFileBookmarks = [record, opaque]
        let model = FileTreePreferences(store: stored)
        let folders = RecentFolderRoots(preferences: model, preservesUnavailableBookmarks: true)
        let files = RecentFileDocuments(preferences: model, preservesUnavailableBookmarks: true)
        #expect(folders.roots == [lexical])
        // A missing path cannot distinguish deletion from an unmounted
        // volume. Migration retains the structured record for a chooser.
        #expect(files.unresolvedBookmarkCount == 2)
        #expect(folders.unresolvedBookmarkCount == 1)
        #expect(folders.resolve(lexical) == nil)
        #expect(stored.recentRootBookmarks == [record, opaque])
        #expect(stored.recentFileBookmarks == [record, opaque])
        #expect(files.documents.isEmpty)
        #expect(files.resolve(lexical) == nil)
        files.pruneMissingFiles()
        #expect(stored.recentFileBookmarks == [record, opaque])
        folders.clear(); files.clear()
        #expect(stored.recentRootBookmarks.isEmpty && stored.recentFileBookmarks.isEmpty)
    }

    @Test func futureRecoveryAndPreferenceMembersAreNotSilentlyAdopted() throws {
        #expect(RecoveryBuffer.admitsInstallationLedger(Data("{}".utf8)))
        #expect(!RecoveryBuffer.admitsInstallationLedger(Data("{\"futureOwnership\":true}".utf8)))
        #expect(!RecoveryBuffer.admitsInstallationLedger(Data("{\"retired\":[],\"retired\":[\"x\"]}".utf8)))
        let filter = Data("{\"showsHiddenFiles\":false,\"supportedFilesOnly\":false,\"foldersFirst\":true,\"future\":1}"
            .utf8)
        #expect(!FileTreeInstallationAdmission.admits(["fileTree.filter": filter]))
        let settings = try InstallationPreferences(
            application: ["appSettings.editor": Data("{\"schemaVersion\":999}".utf8)],
            workspace: nil
        )
        #expect(try !UserDefaultsAppSettingsStore.admitsInstallationPreferences(settings.application))
    }

    @Test func outsideBookmarksAreNeverReinterpretedAsOwnedWorkingRoots() throws {
        let opaque = [Data([255, 0, 1])]
        let roots = try RecentFolderRoots.relocatedInstallationBookmarks(opaque, map: { _ in
            Issue.record("An unreadable bookmark cannot authorize a path"); return nil
        })
        let files = try RecentFileDocuments.relocatedInstallationBookmarks(opaque, map: { _ in
            Issue.record("An unreadable bookmark cannot authorize a path"); return nil
        })
        #expect(roots == opaque && files == opaque)
    }
}
