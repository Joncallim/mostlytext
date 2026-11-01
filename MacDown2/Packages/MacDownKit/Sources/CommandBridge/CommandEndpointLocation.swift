import CryptoKit
import Darwin
import Foundation

public enum CommandEndpointError: Error, Sendable, Equatable {
    case invalidLocation
    case insecureDirectory
    case insecureLock
    case instanceBusy
    case identityChanged
    case ownershipNotEnforced
    case invalidPeer
    case unavailable(Int32)
}

/// The runtime directory comes from the OS per-user runtime location. Resolving
/// an application by PATH, or accepting an endpoint path from a request, is not
/// part of this contract.
public struct CommandEndpointLocation: Sendable, Equatable {
    public let runtimeDirectory: URL
    public let directory: URL
    public let socketPath: String

    /// Use the kernel-selected per-user location, independent of a caller's
    /// TMPDIR environment override. Resolve the OS path's `/var` alias once;
    /// descriptor traversal below still refuses later symlink substitution.
    public static func forCurrentUser(productIdentity: String) throws -> Self {
        let count = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard count > 0, count <= 4096 else { throw CommandEndpointError.invalidLocation }
        var buffer = [CChar](repeating: 0, count: count)
        let actual = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard actual > 0, actual <= count else { throw CommandEndpointError.invalidLocation }
        guard let path = String(bytes: buffer.prefix(actual - 1).map { UInt8(bitPattern: $0) }, encoding: .utf8) else {
            throw CommandEndpointError.invalidLocation
        }
        // Foundation can reintroduce the /var alias while resolving it. Use
        // the POSIX physical spelling required by no-follow traversal.
        guard let resolved = realpath(path, nil) else { throw CommandEndpointError.unavailable(errno) }
        defer { free(resolved) }
        let runtime = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        return try Self(runtimeDirectory: runtime, productIdentity: productIdentity)
    }

    public init(runtimeDirectory: URL, productIdentity: String) throws {
        guard runtimeDirectory.isFileURL, runtimeDirectory.host == nil || runtimeDirectory.host == "localhost",
              !productIdentity.isEmpty, productIdentity.utf8.count <= 1024, !productIdentity.contains("\0") else {
            throw CommandEndpointError.invalidLocation
        }
        let path = runtimeDirectory.path
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.hasPrefix("/"), !path.contains("\0"), !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw CommandEndpointError.invalidLocation
        }
        let digest = SHA256.hash(data: Data(productIdentity.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }.joined()
        let directory = runtimeDirectory.appendingPathComponent("mt-" + digest, isDirectory: true)
        let socketPath = directory.appendingPathComponent("s").path
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw CommandEndpointError.invalidLocation
        }
        self.runtimeDirectory = runtimeDirectory
        self.directory = directory
        self.socketPath = socketPath
    }
}
