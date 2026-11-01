import Foundation
import JSONSupport

public enum CommandRequestCodec {
    private struct Envelope: Encodable {
        var version = CommandProtocol.version
        var type = "open"
        let id: UUID
        let paths: [String]
        let stdin: CommandStdinDescriptor?
        let wait: Bool
    }

    public static func encode(_ request: CommandOpenRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(Envelope(id: request.id, paths: request.paths,
                                                stdin: request.stdin, wait: request.wait))
        guard bytes.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        return bytes
    }

    public static func fingerprint(_ request: CommandOpenRequest) throws -> String {
        try CommandStdinDescriptor.digest(encode(request))
    }

    public static func decode(_ bytes: Data) throws -> CommandOpenRequest {
        guard bytes.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        guard let text = String(data: bytes, encoding: .utf8), case let .valid(root) = JSONParser.parse(text),
              case let .object(members) = root.value else { throw CommandProtocolError.malformedMetadata }
        let fields = try object(members)
        guard Set(fields.keys).isSubset(of: ["version", "type", "id", "paths", "stdin", "wait"]) else {
            throw CommandProtocolError.unknownFields
        }
        guard case let .number(version) = fields["version"]?.value, version == "1" else {
            throw CommandProtocolError.unsupportedVersion
        }
        guard case .string("open") = fields["type"]?.value,
              case let .boolean(wait) = fields["wait"]?.value,
              case let .array(paths) = fields["paths"]?.value else { throw CommandProtocolError.malformedMetadata }
        guard case let .string(rawID) = fields["id"]?.value, let id = UUID(uuidString: rawID) else {
            throw CommandProtocolError.invalidRequestID
        }
        guard paths.count <= CommandProtocol.maximumPaths else { throw CommandProtocolError.tooManyPaths }
        let strings = try paths.map { node in
            guard case let .string(path) = node.value else { throw CommandProtocolError.invalidPath }
            return path
        }
        let stdin = try fields["stdin"].map { try stdinDescriptor($0) }
        return try CommandOpenRequest(id: id, paths: strings, stdin: stdin, wait: wait)
    }

    private static func stdinDescriptor(_ node: JSONNode) throws -> CommandStdinDescriptor {
        guard case let .object(members) = node.value else { throw CommandProtocolError.invalidStdinDescriptor }
        let fields = try object(members)
        guard Set(fields.keys) == ["byteCount", "sha256"],
              case let .number(rawCount) = fields["byteCount"]?.value,
              rawCount.utf8.allSatisfy({ (48 ... 57).contains($0) }), let count = Int(rawCount),
              case let .string(digest) = fields["sha256"]?.value else {
            throw CommandProtocolError.invalidStdinDescriptor
        }
        return try CommandStdinDescriptor(byteCount: count, sha256: digest)
    }

    private static func object(_ members: [JSONObjectMember]) throws -> [String: JSONNode] {
        var result: [String: JSONNode] = [:]
        for member in members {
            guard result.updateValue(member.value, forKey: member.key) == nil else {
                throw CommandProtocolError.malformedMetadata
            }
        }
        return result
    }
}
