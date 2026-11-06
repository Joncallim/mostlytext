import AppKit
import CoreGraphics
import Foundation

/// Hosted-only normal application launch and identity-bound teardown. Never executes under XCTest.
@main
struct NativeCLIAppHost {
    @MainActor
    static func main() async throws {
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
        let application: NSRunningApplication
        let launchDate: Date
        var windows: [[String: Any]]?
        if arguments[1] == "launch" {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty
            else { throw HostError.refused }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.environment = ["MOSTLYTEXT_NATIVE_STARTUP_TRACE": "1"]
            application = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            guard let birth = application.launchDate,
                  application.executableURL?.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
            else { throw HostError.refused }
            launchDate = birth
        } else {
            guard arguments.count == 5, let pid = Int32(arguments[3]), let birth = Double(arguments[4]),
                  let running = NSRunningApplication(processIdentifier: pid),
                  running.bundleURL?.resolvingSymlinksInPath() == appURL,
                  running.executableURL?.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath(),
                  running.launchDate?.timeIntervalSince1970 == birth
            else { throw HostError.refused }
            application = running
            launchDate = Date(timeIntervalSince1970: birth)
            let accepted: Bool
            switch arguments[1] {
            case "inspect":
                windows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]])?
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
                accepted = true
            case "terminate": accepted = application.terminate()
            case "cleanup": accepted = application.forceTerminate()
            default: throw HostError.refused
            }
            guard accepted else { throw HostError.refused }
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while arguments[1] != "inspect", !application.isTerminated, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard arguments[1] == "inspect" || application.isTerminated else { throw HostError.refused }
        }
        var record: [String: Any] = [
            "operation": arguments[1], "pid": application.processIdentifier,
            "birth": launchDate.timeIntervalSince1970, "app": appURL.path,
            "executable": executable.resolvingSymlinksInPath().path,
            "terminated": application.isTerminated
        ]
        if arguments[1] == "inspect" {
            record["window_metadata_available"] = windows != nil
            record["windows"] = windows ?? []
        }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum HostError: Error { case refused }
}
