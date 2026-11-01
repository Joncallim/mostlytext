import CryptoKit
import Foundation

public struct CommandStdinDescriptor: Sendable, Equatable, Encodable {
    public let byteCount: Int
    public let sha256: String

    public init(byteCount: Int, sha256: String) throws {
        guard (0 ... CommandProtocol.maximumStdinBytes).contains(byteCount), sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }) else {
            throw CommandProtocolError.invalidStdinDescriptor
        }
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public init(bytes: Data) throws {
        guard bytes.count <= CommandProtocol.maximumStdinBytes else {
            throw CommandProtocolError.invalidStdinDescriptor
        }
        try self.init(byteCount: bytes.count, sha256: Self.digest(bytes))
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CommandOpenRequest: Sendable {
    public let id: UUID
    public let paths: [String]
    public let stdin: CommandStdinDescriptor?
    public let wait: Bool

    public init(id: UUID = UUID(), paths: [String], stdin: CommandStdinDescriptor? = nil, wait: Bool = false) throws {
        guard paths.count <= CommandProtocol.maximumPaths else { throw CommandProtocolError.tooManyPaths }
        guard paths.allSatisfy(Self.validAbsolutePath) else { throw CommandProtocolError.invalidPath }
        if let stdin {
            _ = try CommandStdinDescriptor(byteCount: stdin.byteCount, sha256: stdin.sha256)
        }
        self.id = id; self.paths = paths; self.stdin = stdin; self.wait = wait
    }

    public static func resolve(_ paths: [String], relativeTo workingDirectory: String) throws -> [String] {
        guard paths.count <= CommandProtocol.maximumPaths else { throw CommandProtocolError.tooManyPaths }
        guard validAbsolutePath(workingDirectory) else { throw CommandProtocolError.invalidPath }
        return try paths.map { path in
            guard !path.isEmpty, path.utf8.count <= CommandProtocol.maximumPathBytes,
                  !path.utf8.contains(0) else { throw CommandProtocolError.invalidPath }
            let absolute = path.hasPrefix("/") ? path
                : workingDirectory + (workingDirectory.hasSuffix("/") ? "" : "/") + path
            guard validAbsolutePath(absolute) else { throw CommandProtocolError.invalidPath }
            return absolute
        }
    }

    static func validAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= CommandProtocol.maximumPathBytes && !path.utf8.contains(0)
    }
}
