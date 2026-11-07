import AppKit
import Darwin
import Foundation

/// Read-only process query. This program has no launch or socket operation.
@main
struct ProductAbsence {
    @MainActor
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_OS"] == "macOS",
              environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              environment["RUNNER_TEMP"] == "/Users/runner/work/_temp",
              getuid() == geteuid(), getuid() > 0,
              let account = getpwuid(getuid()),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              ["/Users/jonathanlim", "/Users/mostlytexttest", "/Volumes/Fast SSD"].allSatisfy({
                  !FileManager.default.fileExists(atPath: $0)
              }),
              CommandLine.arguments.count == 1,
              URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path ==
              "/Users/runner/work/_temp/mostlytext-focus/product-absence"
        else { throw Refusal.host }
        #if !arch(arm64)
            throw Refusal.host
        #else
            let applications = NSRunningApplication
                .runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            guard applications.isEmpty else { throw Refusal.running }
            let record: [String: Any] = [
                "uid": getuid(),
                "product_processes": 0,
                "application_frames_sent": 0,
                "launched_application": false,
            ]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            guard let output = String(bytes: data, encoding: .utf8) else { throw Refusal.host }
            print(output)
        #endif
    }

    enum Refusal: Error { case host, running }
}
