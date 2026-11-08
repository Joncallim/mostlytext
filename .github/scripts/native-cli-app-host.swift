import AppKit
import CoreGraphics
import Foundation

/// Hosted-only normal application launch and identity-bound teardown. Never executes under XCTest.
@main
struct NativeCLIAppHost {
    @MainActor
    static func main() async throws {
        let input = try admittedInput()
        let arguments = input.arguments
        let appURL = input.appURL
        let executable = input.executable
        let application: NSRunningApplication
        let launchDate: Date
        let verifiedPID: pid_t
        var windows: [[String: Any]]?
        if arguments[1] == "launch" {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty
            else { throw HostError.refused }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            application = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            guard let birth = application.launchDate,
                  application.executableURL?.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
            else { throw HostError.refused }
            launchDate = birth
            verifiedPID = application.processIdentifier
            guard verifiedPID > 0 else { throw HostError.refused }
        } else {
            guard arguments.count == 5, let pid = Int32(arguments[3]), let birth = Double(arguments[4]),
                  let running = NSRunningApplication(processIdentifier: pid),
                  running.bundleURL?.resolvingSymlinksInPath() == appURL,
                  running.executableURL?.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath(),
                  running.launchDate?.timeIntervalSince1970 == birth
            else { throw HostError.refused }
            application = running
            launchDate = Date(timeIntervalSince1970: birth)
            verifiedPID = running.processIdentifier
            guard verifiedPID == pid, verifiedPID > 0 else { throw HostError.refused }
            windows = try await operate(arguments[1], application: application, pid: verifiedPID)
        }
        try emitRecord(
            identity: VerifiedIdentity(application: application, pid: verifiedPID, birth: launchDate),
            operation: arguments[1],
            appURL: appURL,
            executable: executable,
            windows: windows
        )
    }

    @MainActor
    private static func admittedInput() throws -> AdmittedInput {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_OS"] == "macOS",
              environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              CommandLine.arguments.count >= 3
        else { throw HostError.refused }
        let arguments = CommandLine.arguments
        let appURL = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
        guard let temporary = environment["RUNNER_TEMP"],
              appURL.path.hasPrefix(URL(fileURLWithPath: temporary).resolvingSymlinksInPath().path + "/"),
              let bundle = Bundle(url: appURL), bundle.bundleIdentifier == "app.mostlytext.MostlyText",
              let executable = bundle.executableURL
        else { throw HostError.refused }
        return AdmittedInput(arguments: arguments, appURL: appURL, executable: executable)
    }

    @MainActor
    private static func operate(_ operation: String, application: NSRunningApplication,
                                pid: pid_t) async throws -> [[String: Any]]? {
        var windows: [[String: Any]]?
        let accepted: Bool
        switch operation {
        case "inspect":
            windows = windowMetadata(for: pid)
            accepted = true
        case "terminate": accepted = application.terminate()
        case "cleanup": accepted = application.forceTerminate()
        default: throw HostError.refused
        }
        guard accepted else { throw HostError.refused }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while operation != "inspect", !application.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard operation == "inspect" || application.isTerminated else { throw HostError.refused }
        return windows
    }

    @MainActor
    private static func windowMetadata(for pid: pid_t) -> [[String: Any]]? {
        (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]])?
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
            .prefix(32).map { row in
                var visible: [String: Any] = [:]
                for key in [kCGWindowNumber, kCGWindowLayer, kCGWindowBounds, kCGWindowIsOnscreen] {
                    visible[key as String] = row[key as String]
                }
                if let name = row[kCGWindowName as String] as? String {
                    visible["name"] = String(name.prefix(160))
                }
                return visible
            }
    }

    @MainActor
    private static func emitRecord(
        identity: VerifiedIdentity, operation: String,
        appURL: URL, executable: URL, windows: [[String: Any]]?
    ) throws {
        var record: [String: Any] = [
            "operation": operation, "pid": identity.pid,
            "observed_pid_after_operation": identity.application.processIdentifier,
            "birth": identity.birth.timeIntervalSince1970, "app": appURL.path,
            "executable": executable.resolvingSymlinksInPath().path,
            "terminated": identity.application.isTerminated,
        ]
        if operation == "inspect" {
            record["window_metadata_available"] = windows != nil
            record["windows"] = windows ?? []
        }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw HostError.refused }
        print(text)
    }

    private struct AdmittedInput {
        let arguments: [String]
        let appURL: URL
        let executable: URL
    }

    @MainActor
    private struct VerifiedIdentity {
        let application: NSRunningApplication
        let pid: pid_t
        let birth: Date
    }

    enum HostError: Error { case refused }
}
