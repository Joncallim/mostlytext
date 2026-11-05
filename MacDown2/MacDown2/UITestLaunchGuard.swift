import Darwin
import Foundation

/// Reject unsafe UI launches before any normal session or recovery store opens.
enum UITestLaunchGuard {
    static let isolatedBundlePrefix = "com.joncallim.MacDown2.UITestIsolated."

    /// The protected UID is baked into this attempt's signed app metadata,
    /// rather than supplied by a launch argument or mutable runtime default.
    static func accountRejection(protectedOwnerUID: String?, realUID: uid_t, effectiveUID: uid_t) -> String? {
        guard let protectedOwnerUID, !protectedOwnerUID.isEmpty,
              protectedOwnerUID.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let ownerUID = uid_t(protectedOwnerUID), ownerUID > 0 else {
            return "The isolated UI test app requires a configured protected owner UID."
        }
        guard realUID == effectiveUID, effectiveUID != 0, effectiveUID != ownerUID else {
            return "The isolated UI test app must run as a separate non-root test user."
        }
        return nil
    }

    static func rejection(
        arguments: [String], testHooksEnabled: Bool, isolatedBuild: Bool = false, bundleID: String? = nil
    ) -> String? {
        let markers = arguments.filter { $0 == "-UITesting" }.count
        if isolatedBuild {
            guard let bundleID, bundleID.hasPrefix(isolatedBundlePrefix),
                  UUID(uuidString: String(bundleID.dropFirst(isolatedBundlePrefix.count))) != nil else {
                return "Incorrect isolated UI test bundle identity."
            }
            guard markers == 1 else { return "The isolated UI test app requires exactly one test marker." }
        }
        if markers > 0, !testHooksEnabled {
            return "UI tests require an app built with UI-test hooks; this build ignores their isolation arguments."
        }
        return nil
    }

    /// The caller supplies an OS-derived private temporary root, not TMPDIR.
    /// Every path must already exist and remain inside that root with no
    /// symlink components; private ownership excludes other users' writes.
    static func validateIsolatedPaths(arguments: [String], trustedRoot: URL, runID: String) -> String? {
        guard UUID(uuidString: runID) != nil,
              arguments.filter({ $0 == "-UITesting" }).count == 1,
              supportedArguments(arguments) else {
            return "Unsupported UI test launch arguments."
        }
        let runRoot = trustedRoot.appendingPathComponent("MostlyTextUITest-" + runID, isDirectory: true)
        guard isOwnedPath(runRoot.path, under: trustedRoot, directory: true) else {
            return "UI test run root must be an owned private temporary directory."
        }
        var rootInfo = stat()
        guard lstat(runRoot.path, &rootInfo) == 0, rootInfo.st_mode & 0o077 == 0 else {
            return "UI test run root must be owner-only."
        }
        let sessions = arguments.indices.filter { arguments[$0] == "-sessionDir" }
        let files = arguments.indices.filter { arguments[$0] == "-openFiles" }
        guard sessions.count == 1, let sessionIndex = sessions.first, sessionIndex + 1 < arguments.count,
              files.count == 1, let filesIndex = files.first, filesIndex + 1 < arguments.count else {
            return "Exactly one session directory and fixture list are required."
        }
        let paths = arguments[filesIndex + 1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !paths.isEmpty, paths.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) }) else {
            return "Invalid fixture list."
        }
        guard arguments[sessionIndex + 1] == runRoot.appendingPathComponent("session").path,
              isOwnedPath(arguments[sessionIndex + 1], under: runRoot, directory: true),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: arguments[sessionIndex + 1]),
              entries.isEmpty else { return "UI test session must be an empty owned temporary directory." }
        let fixtureRoot = runRoot.appendingPathComponent("fixtures", isDirectory: true)
        guard isOwnedPath(fixtureRoot.path, under: runRoot, directory: true),
              paths.allSatisfy({ isOwnedPath($0, under: fixtureRoot, directory: false) }) else {
            return "UI test fixtures must be owned regular files in the private temporary directory."
        }
        return nil
    }

    /// The isolated lane accepts only explicit session/fixture options. Do not
    /// inherit the ordinary Debug parser's concatenated-path compatibility or
    /// accept extra bare paths which AppKit could interpret as document opens.
    private static func supportedArguments(_ arguments: [String]) -> Bool {
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "-UITesting":
                index += 1
            case "-sessionDir", "-openFiles":
                guard index + 1 < arguments.count else { return false }
                index += 2
            default:
                return false
            }
        }
        return !arguments.isEmpty
    }

    private static func isOwnedPath(_ path: String, under root: URL, directory: Bool) -> Bool {
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return false }
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        // Resolve the system's /var alias, but reject symlinks below the trusted root.
        let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        guard resolved.hasPrefix(base + "/"), candidate == resolved ||
            (candidate.hasPrefix("/var/") && "/private" + candidate == resolved) else { return false }
        var cursor = base
        let relative = String(resolved.dropFirst(base.count + 1)).split(separator: "/")
        guard !relative.isEmpty else { return false }
        for (index, part) in relative.enumerated() {
            cursor += "/" + part
            var info = stat()
            guard lstat(cursor, &info) == 0, info.st_uid == geteuid(),
                  info.st_mode & S_IFMT != S_IFLNK, info.st_mode & 0o022 == 0 else { return false }
            let last = index == relative.count - 1
            if last, !directory, info.st_nlink != 1 {
                return false
            }
            let kind = info.st_mode & S_IFMT
            guard last ? kind == (directory ? S_IFDIR : S_IFREG) : kind == S_IFDIR else { return false }
        }
        return true
    }

    static func systemPrivateTemporaryRoot() -> URL? {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) == length else { return nil }
        let root = URL(
            fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            isDirectory: true
        ).resolvingSymlinksInPath()
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else { return nil }
        return root
    }
}
