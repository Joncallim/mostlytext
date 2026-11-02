import AppKit
import Darwin
import Foundation
import MachO
import Security

public enum EmbeddedCommandFailure: Error, Sendable, Equatable {
    case invalidContainer
    case invalidIdentity
    case unverifiedSignature
}

/// Locate only the app containing this executable. No PATH/LaunchServices
/// search, configurable bundle ID or unsigned-launch override is accepted.
public struct EmbeddedCommandApplication: Sendable, Equatable {
    private static let toolName = "macdown2-command"
    public let bundleURL: URL
    public let executableURL: URL
    public let bundleIdentifier: String
    public let displayVersion: String
    let cliURL: URL

    public static func current() throws -> Self {
        var length: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &length)
        guard length > 0, length <= 16384 else { throw EmbeddedCommandFailure.invalidContainer }
        var bytes = [CChar](repeating: 0, count: Int(length))
        guard _NSGetExecutablePath(&bytes, &length) == 0 else { throw EmbeddedCommandFailure.invalidContainer }
        guard let end = bytes.firstIndex(of: 0),
              let path = String(bytes: bytes.prefix(end).map { UInt8(bitPattern: $0) }, encoding: .utf8) else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        return try locate(executableURL: URL(fileURLWithPath: path))
    }

    public static func locate(executableURL: URL) throws -> Self {
        guard executableURL.isFileURL, executableURL.host == nil || executableURL.host == "",
              !executableURL.path.utf8.contains(0), let resolved = realpath(executableURL.path, nil) else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        defer { free(resolved) }
        let cli = URL(fileURLWithPath: String(cString: resolved))
        let macOS = cli.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard cli.lastPathComponent == Self.toolName, macOS.lastPathComponent == "MacOS",
              contents.lastPathComponent == "Contents", app.pathExtension == "app",
              FileManager.default.isExecutableFile(atPath: cli.path)
        else { throw EmbeddedCommandFailure.invalidContainer }
        let infoURL = contents.appendingPathComponent("Info.plist")
        let handle = try FileHandle(forReadingFrom: infoURL)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 65537) ?? Data()
        guard bytes.count <= 65536,
              let info = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              let identity = info["CFBundleIdentifier"] as? String, validIdentity(identity),
              let name = info["CFBundleExecutable"] as? String, validComponent(name), name.lowercased() != Self.toolName
        else { throw EmbeddedCommandFailure.invalidIdentity }
        guard let resolvedMain = realpath(macOS.appendingPathComponent(name).path, nil) else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        defer { free(resolvedMain) }
        let main = URL(fileURLWithPath: String(cString: resolvedMain))
        guard main.deletingLastPathComponent().path == macOS.path,
              FileManager.default.isExecutableFile(atPath: main.path) else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        let version = (info["CFBundleShortVersionString"] as? String) ?? "development"
        let build = (info["CFBundleVersion"] as? String) ?? "unknown"
        guard [version, build].allSatisfy({ $0.utf8.count <= 64 && $0.utf8.allSatisfy { (32 ... 126).contains($0) } })
        else {
            throw EmbeddedCommandFailure.invalidIdentity
        }
        return Self(bundleURL: app, executableURL: main, bundleIdentifier: identity,
                    displayVersion: "\(version) (\(build))", cliURL: cli)
    }

    /// Cold launch requires both the actual embedded CLI's team and a valid
    /// Apple-anchored app signature. Ad-hoc/unsigned development builds fail.
    public func verifyForLaunch() throws {
        var cli: SecStaticCode?
        guard SecStaticCodeCreateWithPath(cliURL as CFURL, [], &cli) == errSecSuccess, let cli,
              SecStaticCodeCheckValidity(cli, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw EmbeddedCommandFailure.unverifiedSignature
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(cli, SecCSFlags(rawValue: kSecCSSigningInformation), &information) ==
            errSecSuccess,
            let values = information as? [String: Any],
            let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
            team.utf8.count == 10,
            team.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) }) else {
            throw EmbeddedCommandFailure.unverifiedSignature
        }
        let expression = "anchor apple generic and identifier \"\(bundleIdentifier)\"" +
            " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        var app: SecStaticCode?
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &app) == errSecSuccess, let app,
              SecStaticCodeCheckValidity(app, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures |
                                             kSecCSCheckNestedCode),
              requirement) == errSecSuccess else {
            throw EmbeddedCommandFailure.unverifiedSignature
        }
    }

    public func launch(until deadline: ContinuousClock.Instant,
                       isCancelled: @escaping @Sendable () -> Bool) async throws {
        try await CommandLaunchWaiter.wait(until: deadline, isCancelled: isCancelled) { ticket in
            Task.detached {
                do {
                    try verifyForLaunch()
                    await MainActor.run {
                        guard ticket.isActive, !isCancelled(), ContinuousClock.now < deadline else { return }
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.createsNewApplicationInstance = false
                        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                            if let error {
                                ticket.finish(.failure(error))
                            } else {
                                ticket.finish(.success(()))
                            }
                        }
                    }
                } catch { ticket.finish(.failure(error)) }
            }
        }
    }

    private static func validComponent(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && ![".", ".."].contains(name) &&
            !name.contains("/") && !name.utf8.contains(0)
    }

    private static func validIdentity(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && name.contains(".") &&
            !name.lowercased().hasPrefix("com.example") &&
            name.utf8.allSatisfy { (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) ||
                $0 == 46 || $0 == 45
            }
    }
}
