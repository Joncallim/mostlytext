import Darwin
import Foundation

/// No domain, profile or receipt access is allowed before the held/host checks.
enum MigrationSeedAdmission {
    static let qualifiedMain = "d29358412585f669264e55e0f3666f456038b228"
    static let futureQualifiedMain = "d29358412585f669264e55e0f3666f456038b228"
    static let root = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-focus", isDirectory: true)

    enum Refusal: Error { case held, host, event, positive }

    static func requireFutureHost() throws {
        guard futureQualifiedMain.count == 40, futureQualifiedMain.allSatisfy(\.isHexDigit) else {
            throw Refusal.held
        }
        try requireHost()
    }

    static func requireHost() throws {
        guard qualifiedMain.count == 40, qualifiedMain.allSatisfy(\.isHexDigit) else {
            throw Refusal.held
        }
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_OS"] == "macOS",
              environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              environment["RUNNER_TEMP"] == root.deletingLastPathComponent().path,
              getuid() == geteuid(), getuid() > 0,
              let account = getpwuid(getuid()), String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 else { throw Refusal.host }
        #if !arch(arm64)
            throw Refusal.host
        #endif
        guard !["/Users/jonathanlim", "/Users/mostlytexttest", "/Volumes/Fast SSD"].contains(where: {
            FileManager.default.fileExists(atPath: $0)
        }), let eventPath = environment["GITHUB_EVENT_PATH"] else { throw Refusal.host }
        let event = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: eventPath)))
            as? [String: Any]
        if let pull = event?["pull_request"] as? [String: Any] {
            guard let head = pull["head"] as? [String: Any], let repo = head["repo"] as? [String: Any],
                  repo["full_name"] as? String == "Joncallim/mostlytext" else { throw Refusal.event }
        } else {
            guard environment["GITHUB_EVENT_NAME"] == "workflow_dispatch" else { throw Refusal.event }
        }
    }

    static func requirePositive() throws -> [String: Any] {
        try requireHost()
        let receipt = try JSONSerialization
            .jsonObject(with: Data(contentsOf: root.appendingPathComponent("receipt.json")))
            as? [String: Any]
        guard let receipt, let results = receipt["ui_results"] as? [String: Any],
              let positive = results["positive"] as? [String: Any],
              positive["selected"] as? String == "HostedFocusDriverTests/PublicFocusTests/testBenignInputControl",
              let summary = positive["summary"] as? [String: Any], let owned = positive["owned"] as? [String: Any],
              let criteria = receipt["criteria"] as? [String: Bool], criteria["benign_control"] == true,
              owned["returncode"] as? Int == 0, owned["timed_out"] as? Bool == false,
              owned["cancelled"] as? Bool == false,
              let cleanup = owned["app_cleanup_requested"] as? [Any], cleanup.isEmpty,
              ["totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0]
              .allSatisfy({ summary[$0.key] as? Int == $0.value }) else { throw Refusal.positive }
        return receipt
    }
}
