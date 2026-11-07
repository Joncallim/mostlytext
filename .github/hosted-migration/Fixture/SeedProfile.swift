import AppKit
import AppSettings
import CryptoKit
import EditorCore
import FileCore
import Foundation
import Themes
import Workspace

/// Generates only a fictional old profile. Never invokes the migration itself.
@main
struct MigrationSeedProfile {
    enum Refusal: Error { case arguments, source, existing, publication }

    @MainActor
    static func main() async throws {
        let action = CommandLine.arguments.dropFirst()
        guard action.isEmpty || action == ["--set-current-indentation-after-first-quit"] ||
            (action.count == 2 && action.first == "--capture-fixed-domains" &&
                ["seeded", "first", "relaunch", "failure"].contains(action.last ?? ""))
        else { throw Refusal.arguments }
        let receipt = try MigrationSeedAdmission.requirePositive()
        try verifySource(receipt)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty else { throw Refusal.publication }
        if action.first == "--capture-fixed-domains", let label = action.last {
            try captureDomains(label: label)
            return
        }
        if action.first == "--set-current-indentation-after-first-quit" {
            try updateCurrentIndentation(receipt)
            return
        }
        let root = MigrationSeedAdmission.root
        let old = try freshSourceDirectory()
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let files = try seedFiles(in: old, root: root)
        let session = try await seedSession(in: old, files: files)
        try publishPreferences(files: files)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let result = SeededMigrationProfile(old: old.path, external: files.external.path,
                                            externalSHA256: digest(Data(externalText.utf8)),
                                            unsavedText: recovered, session: session, themeID: files.themeID,
                                            commandSentinel: files.marker.path)
        try encoder.encode(result).write(
            to: root.appendingPathComponent("migration-seed.json"),
            options: .withoutOverwriting
        )
    }

    private static let externalText = "Generated external migration document\r\nUnicode: cafe\u{301} \u{1F642}\r\n"
    private static let recovered = "MIGRATION_UNSAVED_MANAGED_DRAFT\n"
    private struct Files {
        let external: URL
        let snippet: URL
        let themeID: UUID
        let marker: URL
    }

    private static func freshSourceDirectory() throws -> URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        guard support.standardizedFileURL == support.resolvingSymlinksInPath().standardizedFileURL else {
            throw Refusal.source
        }
        let old = support.appendingPathComponent("MacDown 2", isDirectory: true)
        let current = support.appendingPathComponent("MostlyText", isDirectory: true)
        let original = support.appendingPathComponent("MacDown", isDirectory: true)
        let domains = [
            ApplicationStorageLocations.applicationDomain,
            ApplicationStorageLocations.workspaceDomain,
            ApplicationStorageLocations.developmentDomain,
            ApplicationStorageLocations.developmentWorkspaceDomain,
            "com.uranusjr.macdown",
            "com.uranusjr.macdown.workspace",
        ]
        guard !FileManager.default.fileExists(atPath: old.path),
              !FileManager.default.fileExists(atPath: current.path),
              !FileManager.default.fileExists(atPath: original.path),
              domains.allSatisfy({ UserDefaults.standard.persistentDomain(forName: $0) == nil }) else {
            throw Refusal.existing
        }
        return old
    }

    private static func seedFiles(in old: URL, root: URL) throws -> Files {
        let external = root.appendingPathComponent("documents/migration-external.txt")
        try Data(externalText.utf8).write(to: external, options: .withoutOverwriting)
        let library = SnippetLibrary(snippets: [
            Snippet(id: "migration-fixture", name: "Migration fixture", body: "plain ${0}"),
        ])
        let snippet = old.appendingPathComponent("snippets.json")
        try SnippetStore(fileURL: snippet).save(library)
        let themes = old.appendingPathComponent("Themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: false)
        let theme = try ThemeFile(theme: BundledThemes.light)
        try theme.encoded().write(
            to: themes.appendingPathComponent("migration-fixture.json"),
            options: .withoutOverwriting
        )
        let commands = old.appendingPathComponent("Commands", isDirectory: true)
        try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: false)
        let sentinel = commands.appendingPathComponent("must-not-run.command")
        let marker = root.appendingPathComponent("MIGRATION_COMMAND_RAN")
        let command = "#!/bin/sh\n/usr/bin/touch /Users/runner/work/_temp/mostlytext-focus/MIGRATION_COMMAND_RAN\n"
        try Data(command.utf8).write(to: sentinel, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sentinel.path)
        return Files(external: external, snippet: snippet, themeID: theme.stableID, marker: marker)
    }

    @MainActor
    private static func seedSession(in old: URL, files: Files) async throws -> WorkspaceSession {
        let recovery = RecoveryBuffer(recoveryDirectory: old.appendingPathComponent("Recovery", isDirectory: true))
        var records: [TabRecord] = []
        for url in [files.external, files.snippet] {
            let epoch = try await recovery.mintRecoveryEpoch()
            let document = try FileCore.FileDocument(fileURL: url, recoveryBuffer: recovery, recoveryEpoch: epoch)
                .load()
            if url == files.snippet {
                try await recovery.save(content: recovered, for: document.id, version: 1, epoch: epoch)
            }
            records.append(TabRecord(id: UUID(), fileURL: url, documentRecoveryEpoch: epoch,
                                     cursorPosition: 0, selectionLength: 0, scrollOffset: 0,
                                     encoding: document.encoding, baseSHA256: document.baselineSHA256))
        }
        let session = WorkspaceSession(tabs: records, activeTabID: records.last?.id)
        guard WorkspaceSessionStore(fileURL: old.appendingPathComponent("session.json")).saveSessionVerified(session)
        else {
            throw Refusal.publication
        }
        return session
    }

    @MainActor
    private static func publishPreferences(files: Files) throws {
        let oldPreferences = ["com.joncallim.macdown2.hasCompletedFirstRun": true]
        UserDefaults.standard.setPersistentDomain(
            oldPreferences,
            forName: ApplicationStorageLocations.developmentDomain
        )
        guard let defaults = UserDefaults(suiteName: ApplicationStorageLocations.developmentDomain) else {
            throw Refusal.publication
        }
        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.editor = EditorSettings(indentationWidth: 2)
        guard defaults.bool(forKey: "com.joncallim.macdown2.hasCompletedFirstRun"),
              store.editor.indentationWidth == 2,
              !FileManager.default.fileExists(atPath: files.marker.path) else { throw Refusal.publication }
    }

    @MainActor
    private static func captureDomains(label: String) throws {
        let names = [
            ApplicationStorageLocations.developmentDomain,
            ApplicationStorageLocations.developmentWorkspaceDomain,
            ApplicationStorageLocations.applicationDomain,
            ApplicationStorageLocations.workspaceDomain,
            "com.uranusjr.macdown",
            "com.uranusjr.macdown.workspace",
        ]
        let values: [[String: Any]] = names.map { name in
            if let domain = UserDefaults.standard.persistentDomain(forName: name) {
                return ["domain": name, "present": true, "value": domain]
            }
            return ["domain": name, "present": false]
        }
        let bytes = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try bytes.write(
            to: MigrationSeedAdmission.root.appendingPathComponent("migration-domains-\(label).plist"),
            options: .withoutOverwriting
        )
    }

    @MainActor
    private static func updateCurrentIndentation(_ receipt: [String: Any]) throws {
        guard receipt["migration_first_ui_passed"] as? Bool == true,
              receipt["migration_first_normal_quit_verified"] as? Bool == true,
              let current = UserDefaults(suiteName: ApplicationStorageLocations.applicationDomain),
              let old = UserDefaults(suiteName: ApplicationStorageLocations.developmentDomain) else {
            throw Refusal.publication
        }
        var store = UserDefaultsAppSettingsStore(defaults: current)
        guard store.editor.indentationWidth == 2,
              UserDefaultsAppSettingsStore(defaults: old).editor.indentationWidth == 2 else {
            throw Refusal.publication
        }
        var editor = store.editor
        editor.indentationWidth = 8
        store.editor = editor
        guard store.editor.indentationWidth == 8 else { throw Refusal.publication }
        guard let domain = UserDefaults.standard
            .persistentDomain(forName: ApplicationStorageLocations.applicationDomain) else {
            throw Refusal.publication
        }
        let bytes = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        try bytes.write(
            to: MigrationSeedAdmission.root.appendingPathComponent("migration-current-preferences-after-change.plist"),
            options: .withoutOverwriting
        )
    }

    private static func verifySource(_ receipt: [String: Any]) throws {
        guard let sources = receipt["source_sha256"] as? [String: String],
              let workspace = ProcessInfo.processInfo.environment["GITHUB_WORKSPACE"],
              workspace == "/Users/runner/work/mostlytext/mostlytext",
              ["SeedAdmission.swift", "SeedProfile.swift"].allSatisfy({
                  sources[".github/hosted-migration/Fixture/" + $0] != nil
              }) else { throw Refusal.source }
        for (path, expected) in sources {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw Refusal.source }
            let file = URL(fileURLWithPath: workspace, isDirectory: true).appendingPathComponent(path)
            guard try digest(Data(contentsOf: file)) == expected else { throw Refusal.source }
        }
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SeededMigrationProfile: Encodable {
    let old: String
    let external: String
    let externalSHA256: String
    let unsavedText: String
    let session: WorkspaceSession
    let themeID: UUID
    let commandSentinel: String
}
