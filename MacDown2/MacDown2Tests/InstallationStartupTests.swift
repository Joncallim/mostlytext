import AppSettings
import Darwin
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

@Suite("Required installation startup and managed references")
@MainActor
struct InstallationStartupTests {
    @MainActor private final class Fixture {
        let root: URL
        let app = "app.mostlytext.tests.startup.\(UUID().uuidString)"
        let workspace = "app.mostlytext.tests.workspace.\(UUID().uuidString)"
        let publisher: InstallationPreferencesPublisher
        let store: UserDefaultsAppSettingsStore
        var old: URL {
            root.appendingPathComponent("Old", isDirectory: true)
        }

        var final: URL {
            root.appendingPathComponent("Final", isDirectory: true)
        }

        init() throws {
            var pattern = Array("/private/tmp/mtap-XXXXXX".utf8CString)
            root = try pattern.withUnsafeMutableBufferPointer {
                guard let start = $0.baseAddress,
                      let path = mkdtemp(start) else { throw LegacyMigrationFailure.unavailable(errno) }
                return URL(fileURLWithPath: String(cString: path), isDirectory: true)
            }
            publisher = try InstallationPreferencesPublisher(applicationDomain: app, workspaceDomain: workspace)
            store = try UserDefaultsAppSettingsStore(persistentDomainName: app)
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }

        func cleanup() {
            UserDefaults.standard.removePersistentDomain(forName: app)
            UserDefaults.standard.removePersistentDomain(forName: workspace)
            try? FileManager.default.removeItem(at: root)
        }

        func controller(source: @escaping @MainActor () throws -> InstallationPreferences)
            -> ApplicationMigrationStartup {
            let old = old, final = final, root = root, app = app, workspace = workspace
            return ApplicationMigrationStartup(disabled: false,
                                               publisher: publisher,
                                               makeInstallation: {
                                                   try InstallationMigration(developmentDirectory: old,
                                                                             developmentImportJournal: root
                                                                                 .appendingPathComponent("OldImport"),
                                                                             currentDirectory: final
                                                                                 .appendingPathComponent("State"),
                                                                             destinationDirectory: final,
                                                                             applicationDomain: app,
                                                                             workspaceDomain: workspace)
                                               },
                                               source: source,
                                               validate: {
                                                   try InstallationContentAdmission.validate($0, preferences: $1)
                                               },
                                               relocate: {
                                                   try await InstallationManagedPaths.relocate(from: old, to: $0)
                                               },
                                               makeOptional: { _ in
                                                   LegacyImportStartup(store: self.store, disabled: true,
                                                                       makeJournal: {
                                                                           throw LegacyMigrationFailure.invalidRecord
                                                                       },
                                                                       source: {
                                                                           throw LegacyMigrationFailure.invalidRecord
                                                                       },
                                                                       resolveFont: { _ in nil })
                                               })
        }
    }

    @Test func managedSnippetDraftRelocatesWithExactEpochAndOrdinaryRestore() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let draft = try await seedManagedDraft(fixture)
        let originalBytes = try Data(contentsOf: fixture.old.appendingPathComponent("session.json"))
        return try await verifyManagedDraft(
            fixture,
            snippet: draft.snippet,
            draft: draft.text,
            epoch: draft.epoch,
            originalBytes: originalBytes
        )
    }

    private struct ManagedDraft {
        let snippet: URL
        let text: String
        let epoch: UUID
    }

    private func seedManagedDraft(_ fixture: Fixture) async throws -> ManagedDraft {
        let snippet = fixture.old.appendingPathComponent("snippets.json")
        try Data("{\"version\":1,\"snippets\":[]}".utf8).write(to: snippet)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snippet.path)
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.old.appendingPathComponent("Recovery"))
        let epoch = try await recovery.mintRecoveryEpoch()
        let draft = "{\"version\":1,\"snippets\":[]}\r\n\u{feff}日本語"
        _ = try await recovery.saveCurrentLifetime(
            content: draft,
            for: snippet.absoluteString,
            version: 1,
            epoch: epoch
        )
        let session = WorkspaceSession(tabs: [
            TabRecord(id: UUID(), fileURL: snippet,
                      documentRecoveryEpoch: epoch, cursorPosition: 3,
                      selectionLength: 2),
        ])
        let oldStore = WorkspaceSessionStore(fileURL: fixture.old.appendingPathComponent("session.json"))
        #expect(oldStore.saveSessionVerified(session))
        return ManagedDraft(snippet: snippet, text: draft, epoch: epoch)
    }

    private func verifyManagedDraft(_ fixture: Fixture, snippet _: URL, draft: String,
                                    epoch: UUID, originalBytes: Data) async throws {
        let source = try InstallationPreferences(
            application: ["appSettings.editor": JSONEncoder().encode(EditorSettings(smartHome: false))],
            workspace: ["sidebarVisible": false]
        )
        let controller = fixture.controller { source }
        var ready = 0
        controller.didBecomeReady = { ready += 1 }
        #expect(ready == 0)
        await controller.begin()
        #expect(controller.phase == .ready && ready == 1)
        let locations = try #require(controller.locations)
        let migrated = try #require(WorkspaceSessionStore(fileURL: locations.session).loadSession())
        #expect(migrated.tabs.first?.fileURL == locations.snippets.standardizedFileURL)
        #expect(migrated.tabs.first?.documentRecoveryEpoch == epoch)
        #expect(migrated.tabs.first?.cursorPosition == 3 && migrated.tabs.first?.selectionLength == 2)
        let currentRecovery = RecoveryBuffer(recoveryDirectory: locations.recovery)
        let text = try await currentRecovery.load(
            for: locations.snippets.standardizedFileURL.absoluteString,
            epoch: epoch
        )
        #expect(text?.utf8.elementsEqual(draft.utf8) == true)
        #expect(try Data(contentsOf: fixture.old.appendingPathComponent("session.json")) == originalBytes)
        #expect(try Data(contentsOf: locations.preservedDirectory.appendingPathComponent("session.json")) ==
            originalBytes)
        // No local app/GUI owner exists. The ordinary session model alone can restore this identity.
        let tabs = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: locations.session),
            recoveryBuffer: currentRecovery
        )
        await tabs.restoreSessionIfNeeded()
        #expect(tabs.tabs.first?.document.text.utf8.elementsEqual(draft.utf8) == true,
                "restored count: \(tabs.tabs.count), text: \(String(reflecting: tabs.tabs.first?.document.text))")
    }

    @Test func managedFolderBookmarkWithoutAnAliasRelocatesOnlyInsideOwnedState() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let folder = fixture.old.appendingPathComponent("Themes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let bookmark = try folder.bookmarkData(options: .withSecurityScope)
        let session = WorkspaceSession(tabs: [TabRecord(id: UUID(), folderRootBookmark: bookmark)])
        #expect(WorkspaceSessionStore(fileURL: fixture.old.appendingPathComponent("session.json"))
            .saveSessionVerified(session))
        let source = try InstallationPreferences(application: nil, workspace: nil)
        let controller = fixture.controller { source }
        await controller.begin()
        #expect(controller.phase == .ready)
        let locations = try #require(controller.locations)
        let migrated = try #require(WorkspaceSessionStore(fileURL: locations.session).loadSession())
        #expect(migrated.tabs.first?.folderRootAlias == locations.themes.standardizedFileURL)
        #expect(migrated.tabs.first?.folderRootBookmark != bookmark)
    }

    @Test func interveningSessionPublicationWinsOverCapturedMigrationSnapshot() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let store = WorkspaceSessionStore(fileURL: fixture.old.appendingPathComponent("session.json"))
        let first = WorkspaceSession(tabs: [TabRecord(id: UUID())])
        #expect(store.saveSessionVerified(first))
        let captured = try store.installationSnapshot()
        let later = WorkspaceSession(tabs: [TabRecord(id: UUID())])
        #expect(store.saveSessionVerified(later))
        #expect(!store.publishInstallationSession(first, expecting: captured.rawDigest))
        #expect(store.loadSession()?.tabs.first?.id == later.tabs.first?.id)
    }

    @Test func futureSessionBlocksOwnersAndQuitIsAvailableWithoutPublication() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let future = Data("{\"version\":999,\"tabs\":[]}".utf8)
        let file = fixture.old.appendingPathComponent("session.json")
        try future.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let source = try InstallationPreferences(application: ["legacy": true], workspace: nil)
        let controller = fixture.controller { source }
        var ready = 0; controller.didBecomeReady = { ready += 1 }
        await controller.begin()
        #expect(controller.phase == .blocked && controller.canQuitWithoutSession && ready == 0)
        #expect(try fixture.publisher.snapshot().digests == ["absent", "absent"])
        #expect(try Data(contentsOf: file) == future)
    }

    @Test func populatedTargetRequiresPreservedBranchReviewBeforeReadiness() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        UserDefaults.standard.setPersistentDomain(["current": true], forName: fixture.app)
        let source = try InstallationPreferences(application: ["development": true], workspace: nil)
        let controller = fixture.controller { source }
        var ready = 0; controller.didBecomeReady = { ready += 1 }
        await controller.begin()
        #expect(controller.phase == .preservedReview && ready == 0)
        #expect(controller.hasSeparateDevelopmentBackup)
        await controller.continueWithCurrentInstallation()
        #expect(controller.phase == .ready && ready == 1)
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.app)?["current"] as? Bool == true)
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.app)?["development"] == nil)
    }
}
