import Foundation
import JSONSupport

/// Compatibility and live-instance identity, not application authentication.
public enum CommandInstanceHello {
    public static func encode(instanceID: UUID) throws -> Data {
        struct Envelope: Encodable {
            let version = CommandProtocol.version
            let type = "hello"
            let instance: UUID
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(instance: instanceID))
    }

    public static func decode(_ bytes: Data) throws -> UUID {
        guard bytes.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        guard let text = String(data: bytes, encoding: .utf8),
              case let .valid(root) = JSONParser.parse(text), case let .object(members) = root.value,
              members.count == 3 else { throw CommandProtocolError.invalidResponse }
        var fields: [String: JSONNode] = [:]
        for member in members {
            guard fields.updateValue(member.value, forKey: member.key) == nil else {
                throw CommandProtocolError.invalidResponse
            }
        }
        guard Set(fields.keys) == ["version", "type", "instance"] else { throw CommandProtocolError.invalidResponse }
        guard case .number("1") = fields["version"]?.value else { throw CommandProtocolError.unsupportedVersion }
        guard case .string("hello") = fields["type"]?.value,
              case let .string(raw) = fields["instance"]?.value,
              let id = UUID(uuidString: raw) else { throw CommandProtocolError.invalidResponse }
        return id
    }
}
