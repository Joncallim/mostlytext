import Darwin
import Foundation
import Testing
import Textual

/// Never-merge hosted diagnosis: twenty fixed fresh scenarios, with every outcome retained.
@MainActor
struct BufferedPublicationDiagnosticTests {
    @Test func twentyFreshOriginalJourneysPreserveEveryOutcome() async throws {
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/preview-grant-probe/textual-scenarios")
        try admitAndRecordHost(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try archive("initial", threw: false, root: root)
        for round in 0 ..< 10 {
            for journey in ["production", "revision"] {
                MostlyTextPublicationTrace.reset()
                var threw = false
                do {
                    if journey == "production" {
                        try await ProductionPreviewResourceRoutingTests()
                            .theRealMarkdownWindowCopiesGrantedImagesAndRevokesThemOnSaveAs()
                    } else {
                        try await SecuredMarkdownMountedTests()
                            .aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit()
                    }
                } catch {
                    threw = true
                    Issue.record(error)
                }
                try archive(String(format: "%02d-%@", round, journey), threw: threw, root: root)
            }
        }
        try archive("final", threw: false, root: root)
        MostlyTextPublicationTrace.reset()
    }

    private func admitAndRecordHost(root: URL) throws {
        let parent = root.deletingLastPathComponent()
        guard getuid() == 501, geteuid() == getuid(), let account = getpwuid(getuid()),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD"),
              parent.resolvingSymlinksInPath() == parent,
              FileManager.default.fileExists(atPath: parent.path)
        else { throw DiagnosticError.hostRefused }
        let environment = ProcessInfo.processInfo.environment
        let facts: [String: Any] = [
            "diagnostic_only": true, "qualification_candidate": false,
            "uid": getuid(), "effective_uid": geteuid(), "user": NSUserName(), "home": NSHomeDirectory(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "GITHUB_ACTIONS": environment["GITHUB_ACTIONS"] ?? "<absent>",
            "GITHUB_REPOSITORY": environment["GITHUB_REPOSITORY"] ?? "<absent>",
            "RUNNER_TEMP": environment["RUNNER_TEMP"] ?? "<absent>",
        ]
        try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
            .write(to: parent.appendingPathComponent("textual-diagnostic-host.json"), options: [.withoutOverwriting])
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_TEMP"] == "/Users/runner/work/_temp",
              NSUserName() == "runner", NSHomeDirectory() == "/Users/runner",
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD")
        else { throw DiagnosticError.hostRefused }
    }

    private func archive(_ name: String, threw: Bool, root: URL) throws {
        let snapshot = MostlyTextPublicationTrace.snapshot()
        let value: [String: Any] = [
            "scenario": name, "diagnostic_only": true, "qualification_candidate": false,
            "threw": threw, "overflow": snapshot.overflow, "events": snapshot.events,
        ]
        let destination = root.appendingPathComponent(name + ".json")
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try data.write(to: destination, options: [.withoutOverwriting])
        #expect(!snapshot.overflow, "The fixed diagnostic ledger budget must not truncate observations")
        print(
            "TEXTUAL_SCENARIO name=\(name) events=\(snapshot.events.count) overflow=\(snapshot.overflow) threw=\(threw)"
        )
    }

    private enum DiagnosticError: Error { case hostRefused }
}
