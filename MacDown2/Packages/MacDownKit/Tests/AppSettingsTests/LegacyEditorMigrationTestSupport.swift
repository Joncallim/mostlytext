@testable import AppSettings
import Darwin
import Foundation
import Testing

@MainActor
final class EditorMigrationFixture {
    let root: URL
    let domain = "com.mostlytext.tests.journal.\(UUID().uuidString)"
    let defaults: UserDefaults
    var store: UserDefaultsAppSettingsStore
    var directory: URL {
        root.appendingPathComponent("journal", isDirectory: true)
    }

    init() throws {
        var template = Array("/private/tmp/mtj-XXXXXX".utf8CString)
        root = try template.withUnsafeMutableBufferPointer {
            guard let start = $0.baseAddress, let path = mkdtemp(start) else {
                throw LegacyMigrationFailure.unavailable(errno)
            }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        defaults = try #require(UserDefaults(suiteName: domain))
        store = try UserDefaultsAppSettingsStore(persistentDomainName: domain)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }

    func source(_ value: Bool = false) throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: ["editorSmartHome": value, "editorConvertTabs": false])
    }

    func proposal() throws -> LegacyEditorWriteProposal {
        let source = try source()
        let raw = try store.legacyEditorDestination()
        guard case let .decoded(evidence) = raw else { throw LegacyMigrationFailure.invalidRecord }
        return try LegacyEditorWriteProposal(plan: LegacyImportPlan(source: source, destination: evidence),
                                             source: source, storedDestination: raw,
                                             selected: [.smartHome], replacing: [.smartHome])
    }

    func plan() throws -> LegacyEditorJournalPlan {
        try LegacyEditorJournalPlan(proposal: proposal(), domain: domain,
                                    before: defaults.persistentDomain(forName: domain)?["appSettings.editor"] as? Data)
    }

    func put(_ bytes: Data, named name: String) throws {
        let file = directory.appendingPathComponent(name)
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
