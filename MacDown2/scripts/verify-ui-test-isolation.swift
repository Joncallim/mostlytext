import Darwin
import Foundation

/// Standalone launch-guard controls. No application or app-hosted test starts.
@main
struct UIIsolationChecks {
    struct Fixture {
        let root: URL
        let runID: String
        let session: URL
        let files: URL
        let document: URL

        var arguments: [String] {
            ["app", "-UITesting", "-sessionDir", session.path, "-openFiles", document.path]
        }

        var bundleID: String {
            UITestLaunchGuard.isolatedBundlePrefix + runID
        }

        init() throws {
            let manager = FileManager.default
            root = manager.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("isolation-controls-" + UUID().uuidString, isDirectory: true)
            runID = UUID().uuidString
            let run = root.appendingPathComponent("MostlyTextUITest-" + runID, isDirectory: true)
            session = run.appendingPathComponent("session", isDirectory: true)
            files = run.appendingPathComponent("fixtures", isDirectory: true)
            document = files.appendingPathComponent("a.md")
            for path in [root, run, session, files] {
                try manager.createDirectory(
                    at: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
                )
            }
            try "fixture".write(to: document, atomically: true, encoding: .utf8)
        }
    }

    static func main() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var failures: [String] = []
        var count = 0
        func expect(_ condition: Bool, _ name: String) {
            count += 1
            if !condition {
                failures.append(name)
            }
        }
        checkIdentity(fixture, expect: expect)
        checkAccount(expect: expect)
        try checkPaths(fixture, expect: expect)
        for failure in failures {
            print("FAIL: " + failure)
        }
        print("Launch isolation controls: \(count - failures.count)/\(count) passed; no app launched")
        if !failures.isEmpty {
            exit(1)
        }
    }

    private static func checkAccount(expect: (Bool, String) -> Void) {
        let malformed: [String?] = [nil, "", "0", "-1", "501suffix", " 501", "4294967296"]
        for value in malformed {
            expect(UITestLaunchGuard.accountRejection(
                protectedOwnerUID: value, realUID: 502, effectiveUID: 502
            ) != nil, "missing or malformed protected account: \(value ?? "nil")")
        }
        let identities: [(uid_t, uid_t)] = [(501, 501), (0, 0), (502, 0), (502, 503)]
        for (real, effective) in identities {
            expect(UITestLaunchGuard.accountRejection(
                protectedOwnerUID: "501", realUID: real, effectiveUID: effective
            ) != nil, "unsafe test process identity: \(real)/\(effective)")
        }
        expect(UITestLaunchGuard.accountRejection(
            protectedOwnerUID: "501", realUID: 502, effectiveUID: 502
        ) == nil, "separate non-root test identity")
    }

    private static func checkIdentity(_ fixture: Fixture, expect: (Bool, String) -> Void) {
        func rejected(_ arguments: [String], hooks: Bool = true, bundle: String? = nil) -> Bool {
            UITestLaunchGuard.rejection(
                arguments: arguments, testHooksEnabled: hooks, isolatedBuild: true,
                bundleID: bundle ?? fixture.bundleID
            ) != nil
        }
        expect(!rejected(fixture.arguments), "valid isolated identity")
        expect(rejected(["app"]), "missing marker")
        expect(rejected(fixture.arguments + ["-UITesting"]), "duplicate marker")
        expect(rejected(fixture.arguments, hooks: false), "isolated build without hooks")
        expect(rejected(fixture.arguments, bundle: "com.joncallim.MacDown2"), "ordinary app identity")
        expect(rejected(fixture.arguments, bundle: UITestLaunchGuard.isolatedBundlePrefix + "invalid"), "invalid UUID")
        expect(UITestLaunchGuard.rejection(arguments: fixture.arguments, testHooksEnabled: false) != nil,
               "Release rejects requested test hooks")
        expect(UITestLaunchGuard.rejection(arguments: ["app"], testHooksEnabled: false) == nil,
               "ordinary Release launch")
        expect(UITestLaunchGuard.systemPrivateTemporaryRoot() != nil, "OS private temporary root")
    }

    private static func checkPaths(_ fixture: Fixture, expect: (Bool, String) -> Void) throws {
        func accepted(_ arguments: [String]) -> Bool {
            UITestLaunchGuard.validateIsolatedPaths(
                arguments: arguments, trustedRoot: fixture.root, runID: fixture.runID
            ) == nil
        }
        let args = fixture.arguments
        expect(accepted(args), "valid disposable paths")
        let missingMarker = ["app", "-sessionDir", fixture.session.path, "-openFiles", fixture.document.path]
        for (name, arguments) in [
            ("missing marker in path validation", missingMarker),
            ("duplicate marker in path validation", args + ["-UITesting"]),
            ("duplicate session", args + ["-sessionDir", fixture.session.path]),
            ("missing session value", ["app", "-UITesting", "-sessionDir"]),
            ("missing fixture value", Array(args.dropLast())),
            ("unknown option", args + ["-unexpected", "value"]),
            ("folder access", args + ["-openFolder", fixture.root.path]),
            ("bare file argument", args + [fixture.document.path]),
            ("legacy concatenated files", args + ["-openFiles" + fixture.document.path]),
            ("empty fixture list", Array(args.dropLast()) + [""]),
            ("empty fixture component", Array(args.dropLast()) + [fixture.document.path + ","]),
            ("duplicate fixture option", args + ["-openFiles", fixture.document.path]),
        ] {
            expect(!accepted(arguments), name)
        }
        try checkFileKinds(fixture, accepted: accepted, expect: expect)
        try "occupied".write(to: fixture.session.appendingPathComponent("existing"), atomically: true, encoding: .utf8)
        expect(!accepted(args), "nonempty session")
    }

    private static func checkFileKinds(
        _ fixture: Fixture, accepted: ([String]) -> Bool, expect: (Bool, String) -> Void
    ) throws {
        let manager = FileManager.default
        let outside = fixture.root.appendingPathComponent("outside")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = fixture.files.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: fixture.document)
        let hardlink = fixture.files.appendingPathComponent("hardlink")
        try manager.linkItem(at: outside, to: hardlink)
        let spaced = fixture.files.appendingPathComponent("trailing ")
        try "spaced".write(to: spaced, atomically: true, encoding: .utf8)
        for (name, url) in [
            ("symlink fixture", link), ("hardlinked fixture", hardlink),
            ("outside fixture root", outside), ("whitespace changed by parser", spaced),
            ("directory as fixture", fixture.files),
        ] {
            expect(!accepted(Array(fixture.arguments.dropLast()) + [url.path]), name)
        }
        try manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: fixture.document.path)
        expect(!accepted(fixture.arguments), "writable fixture")
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.document.path)
        try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fixture.files.path)
        expect(!accepted(fixture.arguments), "writable fixture directory")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.files.path)
    }
}
