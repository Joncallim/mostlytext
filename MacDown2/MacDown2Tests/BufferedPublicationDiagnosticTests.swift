import Foundation
import Testing
import Textual

/// Never-merge hosted diagnosis: twenty fixed fresh scenarios, with every outcome retained.
@MainActor
struct BufferedPublicationDiagnosticTests {
    @Test func twentyFreshOriginalJourneysPreserveEveryOutcome() async throws {
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/preview-grant-probe/textual-scenarios")
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_TEMP"] == "/Users/runner/work/_temp",
              NSUserName() == "runner", NSHomeDirectory() == "/Users/runner",
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD")
        else { throw DiagnosticError.hostRefused }
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
