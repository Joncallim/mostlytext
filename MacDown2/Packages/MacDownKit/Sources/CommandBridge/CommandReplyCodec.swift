import Foundation
import JSONSupport

/// Wire replies carry stable codes and request targets, never human diagnostics
/// or document source. Both sides enforce the same metadata frame ceiling.
public enum CommandReplyCodec {
    private struct Target: Encodable {
        let kind: String
        let index: Int?

        init(_ target: CommandOpenTarget) {
            switch target {
            case let .path(index): kind = "path"; self.index = index
            case .stdin: kind = "stdin"; index = nil
            case .activation: kind = "activation"; index = nil
            }
        }
    }

    private struct Failure: Encodable {
        let target: Target
        let reason: String
    }

    private struct Envelope: Encodable {
        var version = CommandProtocol.version
        let type: String
        let id: UUID
        var openedCount: Int?
        var failures: [Failure]?
        var reason: String?
    }

    public static func encode(_ event: CommandReceiptEvent) throws -> Data {
        let envelope: Envelope
        switch event {
        case let .accepted(id, openedCount, failures):
            try validate(openedCount: openedCount, failures: failures)
            envelope = Envelope(type: "accepted", id: id, openedCount: openedCount,
                                failures: failures
                                    .map { Failure(target: Target($0.target), reason: $0.reason.rawValue) })
        case let .finished(id):
            envelope = Envelope(type: "finished", id: id)
        case let .rejected(id, reason):
            envelope = Envelope(type: "rejected", id: id, reason: reason.rawValue)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        return bytes
    }

    public static func decode(_ bytes: Data) throws -> CommandReceiptEvent {
        guard bytes.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        guard let text = String(data: bytes, encoding: .utf8), case let .valid(root) = JSONParser.parse(text),
              case let .object(members) = root.value else { throw CommandProtocolError.invalidResponse }
        let fields = try object(members)
        guard case .number("1") = fields["version"]?.value else { throw CommandProtocolError.unsupportedVersion }
        guard case let .string(rawID) = fields["id"]?.value, let id = UUID(uuidString: rawID),
              case let .string(type) = fields["type"]?.value else { throw CommandProtocolError.invalidResponse }
        switch type {
        case "accepted":
            return try accepted(fields, id: id)
        case "finished":
            guard Set(fields.keys) == ["version", "type", "id"] else { throw CommandProtocolError.invalidResponse }
            return .finished(requestID: id)
        case "rejected":
            guard Set(fields.keys) == ["version", "type", "id", "reason"],
                  let reason = reason(fields["reason"]) else { throw CommandProtocolError.invalidResponse }
            return .rejected(requestID: id, reason: reason)
        default:
            throw CommandProtocolError.invalidResponse
        }
    }

    private static func accepted(_ fields: [String: JSONNode], id: UUID) throws -> CommandReceiptEvent {
        guard Set(fields.keys) == ["version", "type", "id", "openedCount", "failures"],
              let count = integer(fields["openedCount"], maximum: CommandProtocol.maximumPaths + 1),
              case let .array(nodes) = fields["failures"]?.value,
              nodes.count <= CommandProtocol.maximumPaths + 1 else { throw CommandProtocolError.invalidResponse }
        let failures = try nodes.map(failure)
        try validate(openedCount: count, failures: failures)
        return .accepted(requestID: id, openedCount: count, failures: failures)
    }

    private static func failure(_ node: JSONNode) throws -> CommandOpenFailure {
        guard case let .object(members) = node.value else { throw CommandProtocolError.invalidResponse }
        let fields = try object(members)
        guard Set(fields.keys) == ["target", "reason"], let reason = reason(fields["reason"]),
              case let .object(targetMembers) = fields["target"]?.value else {
            throw CommandProtocolError.invalidResponse
        }
        let target = try object(targetMembers)
        switch target["kind"]?.value {
        case .string("path"):
            guard Set(target.keys) == ["kind", "index"],
                  let index = integer(target["index"], maximum: CommandProtocol.maximumPaths - 1) else {
                throw CommandProtocolError.invalidResponse
            }
            return CommandOpenFailure(target: .path(index), reason: reason)
        case .string("stdin"), .string("activation"):
            guard Set(target.keys) == ["kind"] else { throw CommandProtocolError.invalidResponse }
            return CommandOpenFailure(target: target["kind"]?.value == .string("stdin") ? .stdin : .activation,
                                      reason: reason)
        default:
            throw CommandProtocolError.invalidResponse
        }
    }

    private static func reason(_ node: JSONNode?) -> CommandOpenFailure.Reason? {
        guard case let .string(value) = node?.value else { return nil }
        return CommandOpenFailure.Reason(rawValue: value)
    }

    private static func integer(_ node: JSONNode?, maximum: Int) -> Int? {
        guard case let .number(raw) = node?.value, !raw.isEmpty,
              raw.utf8.allSatisfy({ (48 ... 57).contains($0) }), let value = Int(raw),
              value <= maximum else { return nil }
        return value
    }

    private static func object(_ members: [JSONObjectMember]) throws -> [String: JSONNode] {
        var fields: [String: JSONNode] = [:]
        for member in members {
            guard fields.updateValue(member.value, forKey: member.key) == nil else {
                throw CommandProtocolError.invalidResponse
            }
        }
        return fields
    }

    private static func validate(openedCount: Int, failures: [CommandOpenFailure]) throws {
        let maximum = CommandProtocol.maximumPaths + 1
        guard (0 ... maximum).contains(openedCount), failures.count <= maximum - openedCount,
              Set(failures.map(\.target)).count == failures.count else { throw CommandProtocolError.invalidResponse }
        for failure in failures {
            if case let .path(index) = failure.target, !(0 ..< CommandProtocol.maximumPaths).contains(index) {
                throw CommandProtocolError.invalidResponse
            }
        }
    }
}
