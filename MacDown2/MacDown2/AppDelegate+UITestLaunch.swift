import Darwin
import Foundation

extension AppDelegate {
    static func prepareUITestState(sessionDirectory: URL) -> UserDefaults {
        do {
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Unable to create isolated UI test session: \(error)")
        }
        let suite = "com.joncallim.macdown2.uitest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Unable to create isolated UI test preferences.")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Validate test-only launch requests before persistent stores are constructed.
    static func validateUITestLaunch() {
        // Inspect raw arguments before choosing any persistent stores. Release
        // builds ignore test hooks and must never silently open real user data
        // when a UI runner requests an isolated test session.
        #if DEBUG || ISSUE117_NATIVE_ACCEPTANCE
            let testHooksEnabled = true
        #else
            let testHooksEnabled = false
        #endif
        #if UITEST_ISOLATED
            let isolatedBuild = true
        #else
            let isolatedBuild = false
        #endif
        let rawArguments = ProcessInfo.processInfo.arguments
        if let reason = UITestLaunchGuard.rejection(
            arguments: rawArguments,
            testHooksEnabled: testHooksEnabled,
            isolatedBuild: isolatedBuild,
            bundleID: Bundle.main.bundleIdentifier
        ) {
            fatalError(reason)
        }
        #if UITEST_ISOLATED
            if let reason = UITestLaunchGuard.accountRejection(
                protectedOwnerUID: Bundle.main.object(forInfoDictionaryKey: "MostlyTextUITestOwnerUID") as? String,
                realUID: getuid(), effectiveUID: geteuid()
            ) {
                fatalError(reason)
            }
            guard let temporaryRoot = UITestLaunchGuard.systemPrivateTemporaryRoot() else {
                fatalError("Cannot determine a private system temporary directory for UI testing.")
            }
            guard let bundleID = Bundle.main.bundleIdentifier else {
                fatalError("The isolated UI test app has no bundle identity.")
            }
            let runID = String(bundleID.dropFirst(UITestLaunchGuard.isolatedBundlePrefix.count))
            if let reason = UITestLaunchGuard.validateIsolatedPaths(
                arguments: rawArguments, trustedRoot: temporaryRoot, runID: runID
            ) {
                fatalError(reason)
            }
        #endif
    }
}
