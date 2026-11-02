@testable import AppSettings
import Darwin
import Foundation
import Testing

@MainActor
final class InstallationFixture {
    let root: URL
    let appDomain = "app.mostlytext.tests.install.\(UUID().uuidString)"
    let workspaceDomain = "app.mostlytext.tests.workspace.\(UUID().uuidString)"
    let publisher: InstallationPreferencesPublisher
    var development: URL {
        root.appendingPathComponent("Development", isDirectory: true)
    }

    var previousJournal: URL {
        root.appendingPathComponent("EditorImport", isDirectory: true)
    }

    var destination: URL {
        root.appendingPathComponent("Final", isDirectory: true)
    }

    var current: URL {
        destination.appendingPathComponent("State", isDirectory: true)
    }

    init() throws {
        var template = Array("/private/tmp/mti-XXXXXX".utf8CString)
        root = try template.withUnsafeMutableBufferPointer {
            guard let start = $0.baseAddress,
                  let path = mkdtemp(start) else { throw LegacyMigrationFailure.unavailable(errno) }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        publisher = try InstallationPreferencesPublisher(applicationDomain: appDomain, workspaceDomain: workspaceDomain)
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: appDomain)
        UserDefaults.standard.removePersistentDomain(forName: workspaceDomain)
        try? FileManager.default.removeItem(at: root)
    }

    func makeActor(checkpoint: (@Sendable (InstallationMigration.Checkpoint) throws -> Void)? = nil) throws
        -> InstallationMigration {
        if let checkpoint {
            return try InstallationMigration(
                developmentDirectory: development,
                developmentImportJournal: previousJournal,
                currentDirectory: current,
                destinationDirectory: destination,
                applicationDomain: appDomain,
                workspaceDomain: workspaceDomain,
                checkpoint: checkpoint
            )
        }
        return try InstallationMigration(developmentDirectory: development, developmentImportJournal: previousJournal,
                                         currentDirectory: current, destinationDirectory: destination,
                                         applicationDomain: appDomain, workspaceDomain: workspaceDomain)
    }

    func source() throws -> InstallationPreferences {
        try InstallationPreferences(
            application: [
                "appSettings.editor": JSONEncoder().encode(EditorSettings(smartHome: false)),
                "opaque": Data([0, 255]),
            ],
            workspace: ["sidebarVisible": false]
        )
    }

    func put(_ text: String, relative: String) throws {
        let url = development.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func finish(_ actor: InstallationMigration, prepared: PreparedInstallationMigration,
                source: InstallationPreferences) async throws -> PreparedInstallationMigration {
        let published = try await actor.publishFiles(prepared)
        if !published.preferencesAcknowledged {
            try await actor.revalidateSources(published)
            try publisher.publish(desired: published.desiredPreferences, before: published.beforePreferenceDigests) {
                let actual = try source.digests
                #expect(actual == published.sourcePreferenceDigests)
            }
            try await actor.acknowledgePreferences(published)
        }
        try await actor.complete(published)
        return published
    }
}
