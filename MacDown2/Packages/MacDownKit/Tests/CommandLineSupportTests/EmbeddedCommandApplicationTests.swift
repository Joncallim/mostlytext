import CommandLineSupport
import Foundation
import Testing

struct EmbeddedCommandApplicationTests {
    private func withApp(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Mostly Text.app")
        let folder = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cli = folder.appendingPathComponent("mostlytext-cli")
        for file in [cli, folder.appendingPathComponent("MostlyText")] {
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let metadata = [
            "CFBundlePackageType": "APPL", "CFBundleIdentifier": "com.mostlytext.test-cli",
            "CFBundleExecutable": "MostlyText", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "5",
        ]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try body(app, cli)
    }

    @Test func directAndExplicitUserBinSymlinkLocateOnlyTheEnclosingApp() throws {
        try withApp { app, cli in
            let direct = try EmbeddedCommandApplication.locate(executableURL: cli)
            #expect(direct.bundleURL.resolvingSymlinksInPath() == app.resolvingSymlinksInPath())
            #expect(direct.bundleIdentifier == "com.mostlytext.test-cli")
            #expect(direct.displayVersion == "0.1.0 (5)")
            let link = app.deletingLastPathComponent().appendingPathComponent("user-bin-command")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cli)
            #expect(try EmbeddedCommandApplication.locate(executableURL: link) == direct)
            #expect(throws: EmbeddedCommandFailure.unverifiedSignature) { try direct.verifyForLaunch() }
        }
    }

    @Test func unrelatedLocationMissingMetadataAndEscapingMainExecutableFailClosed() throws {
        try withApp { app, cli in
            let outside = app.deletingLastPathComponent().appendingPathComponent("outside")
            try Data().write(to: outside)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) {
                try EmbeddedCommandApplication.locate(executableURL: outside)
            }
            let main = cli.deletingLastPathComponent().appendingPathComponent("MostlyText")
            try FileManager.default.removeItem(at: main)
            try FileManager.default.createSymbolicLink(at: main, withDestinationURL: outside)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) {
                try EmbeddedCommandApplication.locate(executableURL: cli)
            }
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Info.plist"))
            #expect(throws: (any Error).self) { try EmbeddedCommandApplication.locate(executableURL: cli) }
        }
    }
}
