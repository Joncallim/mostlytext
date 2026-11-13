import Foundation

extension AppDelegate {
    // MARK: - Launch argument parsing

    /// The arguments the test hooks (`-UITesting`, `-sessionDir`, `-openFiles`, `-openFolder`) are read from.
    /// Debug builds, the separately flagged #117 acceptance app, and the
    /// hosted math UI diagnostic build only. An ordinary Release build rejects
    /// a UI-test request before selecting stores instead of ignoring isolation.
    static var launchArguments: [String] {
        #if ISSUE117_NATIVE_ACCEPTANCE
            let args = ProcessInfo.processInfo.arguments
            precondition(
                args.contains("-Issue117Acceptance") && args.contains("-UITesting")
                    && args.contains("-sessionDir") && args.contains("-openFiles"),
                "Launch the isolated #117 acceptance build with its retained launcher"
            )
            return args
        #elseif DEBUG || MATH_UI_DIAGNOSTIC
            ProcessInfo.processInfo.arguments
        #else
            []
        #endif
    }

    static func sessionDirectory(from args: [String]) -> URL {
        if let index = args.firstIndex(of: "-sessionDir"), index + 1 < args.count {
            return URL(fileURLWithPath: args[index + 1])
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    static func openFilesPaths(from args: [String]) -> [String] {
        if let index = args.firstIndex(of: "-openFiles"), index + 1 < args.count {
            let remainder = args[index + 1]
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if let arg = args.first(where: { $0.hasPrefix("-openFiles") }) {
            let prefix = "-openFiles"
            let remainder = String(arg.dropFirst(prefix.count))
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    /// UI-test hook: `-fileMonitorDebounceMs <n>` (with `-UITesting`, Debug only via `launchArguments`) lengthens
    /// the external-file monitor's debounce, so a UI test can act on a conflict banner after deleting the backing
    /// file but before the monitor itself notices the deletion — otherwise the default 150 ms debounce always
    /// beats XCUITest's ~300 ms click and that action's own "file vanished" path can never be reached.
    /// `nil` (the monitor's own default) for every other launch.
    static var uiTestingFileMonitorDebounce: Duration? {
        let args = launchArguments
        guard args.contains("-UITesting"),
              let index = args.firstIndex(of: "-fileMonitorDebounceMs"), index + 1 < args.count,
              let milliseconds = Int(args[index + 1]), milliseconds >= 0
        else { return nil }
        return .milliseconds(milliseconds)
    }

    static func openFolderPath(from args: [String]) -> String? {
        guard let index = args.firstIndex(of: "-openFolder"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
