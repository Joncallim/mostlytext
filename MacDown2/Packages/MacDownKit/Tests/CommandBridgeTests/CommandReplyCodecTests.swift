import CommandBridge
import Foundation
import Testing

struct CommandReplyCodecTests {
    private let id = UUID()

    @Test func eventsRoundTripWithAllTargetKindsAndStableReasons() throws {
        let failures = [
            CommandOpenFailure(target: .path(0), reason: .missingFile),
            CommandOpenFailure(target: .stdin, reason: .invalidEncoding),
            CommandOpenFailure(target: .activation, reason: .unavailable),
        ]
        let events: [CommandReceiptEvent] = [
            .accepted(requestID: id, openedCount: 2, failures: failures),
            .finished(requestID: id),
            .rejected(requestID: id, reason: .recoveryUnavailable),
        ]
        for event in events {
            let bytes = try CommandReplyCodec.encode(event)
            #expect(try CommandReplyCodec.decode(bytes) == event)
            #expect(try CommandReplyCodec.encode(CommandReplyCodec.decode(bytes)) == bytes)
        }
    }

    @Test(arguments: ["-1", "1.0", "1e0", "true", "34", "99999999999999999999999"])
    func countsMustBeBoundedCanonicalIntegers(_ raw: String) {
        let text = "{\"version\":1,\"type\":\"accepted\",\"id\":\"\(id)\",\"openedCount\":\(raw),\"failures\":[]}"
        #expect(throws: CommandProtocolError.invalidResponse) { try CommandReplyCodec.decode(Data(text.utf8)) }
    }

    @Test func exactMembersAndTypesAreRequiredAtEveryLevel() throws {
        let base = try CommandReplyCodec.encode(.accepted(requestID: id, openedCount: 1, failures: []))
        let object = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let invalidFailures: [[String: Any]] = [
            ["target": ["kind": "path", "index": 32], "reason": "unreadable"],
            ["target": ["kind": "path", "index": -1], "reason": "unreadable"],
            ["target": ["kind": "path", "index": true], "reason": "unreadable"],
            ["target": ["kind": "stdin", "index": 0], "reason": "unreadable"],
            ["target": ["kind": "other"], "reason": "unreadable"],
            ["target": ["kind": "activation"], "reason": "madeUp"],
            ["target": ["kind": "stdin"], "reason": "unreadable", "extra": 1],
        ]
        var corruptions: [[String: Any]] = invalidFailures.map { failure in
            object.merging(["failures": [failure]]) { _, new in new }
        }
        corruptions += [
            object.merging(["extra": 1]) { _, new in new },
            object.merging(["failures": NSNull()]) { _, new in new },
            object.merging(["id": "not-a-uuid"]) { _, new in new },
            object.merging(["type": "execute"]) { _, new in new },
            object.filter { $0.key != "openedCount" },
        ]
        for corruption in corruptions {
            #expect(throws: CommandProtocolError.self) {
                try CommandReplyCodec.decode(JSONSerialization.data(withJSONObject: corruption))
            }
        }
    }

    @Test(arguments: [
        "{\"version\":1,\"version\":1}", "{\"version\":1,\"\\u0076ersion\":1}",
        "[]", "{\"version\":1.0}", "{\"version\":true}", "{\"version\":2}",
    ])
    func malformedAndUnsupportedEnvelopesAreRejected(_ text: String) {
        #expect(throws: CommandProtocolError.self) { try CommandReplyCodec.decode(Data(text.utf8)) }
    }

    @Test func duplicateNestedMembersAndTargetsAreRejected() throws {
        let prefix = "{\"version\":1,\"type\":\"accepted\",\"id\":\"\(id)\",\"openedCount\":0,\"failures\":["
        for target in ["{\"kind\":\"stdin\",\"kind\":\"stdin\"}", "{\"kind\":\"path\",\"index\":0,\"index\":0}"] {
            let raw = prefix + "{\"target\":\(target),\"reason\":\"unreadable\"}]}"
            #expect(throws: CommandProtocolError.invalidResponse) { try CommandReplyCodec.decode(Data(raw.utf8)) }
        }
        let failure = CommandOpenFailure(target: .stdin, reason: .unreadable)
        #expect(throws: CommandProtocolError.invalidResponse) {
            try CommandReplyCodec.encode(.accepted(requestID: id, openedCount: 0, failures: [failure, failure]))
        }
    }

    @Test func terminalRepliesRejectExtraneousFields() {
        for suffix in [",\"openedCount\":0", ",\"failures\":[]", ",\"reason\":null"] {
            let raw = "{\"version\":1,\"type\":\"finished\",\"id\":\"\(id)\"\(suffix)}"
            #expect(throws: CommandProtocolError.invalidResponse) { try CommandReplyCodec.decode(Data(raw.utf8)) }
        }
        let raw = "{\"version\":1,\"type\":\"rejected\",\"id\":\"\(id)\",\"reason\":\"future\"}"
        #expect(throws: CommandProtocolError.invalidResponse) { try CommandReplyCodec.decode(Data(raw.utf8)) }
    }

    @Test func byteAndAggregateLimitsApplyInBothDirections() {
        #expect(throws: CommandProtocolError.frameTooLarge) {
            try CommandReplyCodec.decode(Data(repeating: 32, count: CommandProtocol.maximumFrameBytes + 1))
        }
        #expect(throws: CommandProtocolError.invalidResponse) { try CommandReplyCodec.decode(Data([0xFF])) }
        #expect(throws: CommandProtocolError.invalidResponse) {
            try CommandReplyCodec.encode(.accepted(requestID: id, openedCount: 34, failures: []))
        }
        #expect(throws: CommandProtocolError.invalidResponse) {
            try CommandReplyCodec.encode(.accepted(requestID: id, openedCount: 33,
                                                   failures: [.init(target: .stdin, reason: .unavailable)]))
        }
    }
}
