import Darwin
import Foundation
import OSLog

#if !arch(arm64)
    #error("The observation control requires the hosted ARM64 runner")
#endif

@main
enum ObserverControl {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let account = getpwuid(getuid()),
              getuid() == 501, geteuid() == getuid(),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              environment["GITHUB_ACTIONS"] == "true",
              environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              environment["RUNNER_TEMP"] == "/Users/runner/work/_temp",
              CommandLine.arguments.count == 2,
              URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
              == "/Users/runner/work/_temp/mostlytext-qldeadline/observer-control",
              let nonce = UUID(uuidString: CommandLine.arguments[1]),
              nonce.uuidString == CommandLine.arguments[1]
        else {
            throw NSError(domain: "MostlyTextObserverControl", code: 1)
        }
        Logger(subsystem: "app.mostlytext.qldeadlineobserver", category: "channel")
            .notice("QL_OBSERVER_CONTROL nonce=\(nonce.uuidString, privacy: .public)")
    }
}
