import CommandBridge
import Foundation
import Testing

struct CommandRequestCodecTests {
    private let id = UUID()

    @Test func structuredPathsAndStdinRoundTripWithoutShellOrSourceNormalization() throws {
        let paths = ["/tmp/a b", "/tmp/a\nb", "/tmp/$(touch never)", "/tmp/`never`", "/tmp/文🙂"]
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("text\r\n".utf8)
        let request = try CommandOpenRequest(
            id: id,
            paths: paths,
            stdin: CommandStdinDescriptor(bytes: bytes),
            wait: true
        )
        let encoded = try CommandRequestCodec.encode(request)
        let result = try CommandRequestCodec.decode(encoded)
        #expect(result.id == id)
        #expect(result.paths.map { Data($0.utf8) } == paths.map { Data($0.utf8) })
        #expect(result.stdin == request.stdin)
        #expect(result.wait)
        #expect(try CommandRequestCodec.encode(result) == encoded)
    }

    @Test func relativePathJoiningPreservesSymlinkSensitiveDotComponents() throws {
        let result = try CommandOpenRequest.resolve(["link/../file", "./文", "/absolute"], relativeTo: "/caller")
        #expect(result == ["/caller/link/../file", "/caller/./文", "/absolute"])
        #expect(try CommandOpenRequest.resolve(["x"], relativeTo: "/") == ["/x"])
    }

    @Test func emptyStdinIsDifferentFromActivationAndFingerprintsBindExactPayloads() throws {
        let activate = try CommandOpenRequest(id: id, paths: [])
        let stdin = try CommandOpenRequest(id: id, paths: [], stdin: CommandStdinDescriptor(bytes: Data()))
        #expect(try CommandRequestCodec.fingerprint(activate) != CommandRequestCodec.fingerprint(stdin))
        let composed = try CommandOpenRequest(id: id, paths: ["/é"])
        let decomposed = try CommandOpenRequest(id: id, paths: ["/e\u{301}"])
        #expect(try CommandRequestCodec.fingerprint(composed) != CommandRequestCodec.fingerprint(decomposed))
        let wait = try CommandOpenRequest(id: id, paths: [], wait: true)
        #expect(try CommandRequestCodec.fingerprint(activate) != CommandRequestCodec.fingerprint(wait))
    }

    @Test(arguments: ["../relative", "", "/nul\0suffix", "/" + String(repeating: "a", count: 4096)])
    func invalidPathsNeverBecomeRequests(_ path: String) {
        #expect(throws: CommandProtocolError.invalidPath) { try CommandOpenRequest(paths: [path]) }
    }

    @Test func countAndEncodedSizeLimitsAreCheckedSeparately() throws {
        #expect(throws: CommandProtocolError.tooManyPaths) {
            try CommandOpenRequest(paths: Array(repeating: "/x", count: 33))
        }
        let validPath = "/" + String(repeating: "a", count: 4095)
        let request = try CommandOpenRequest(paths: Array(repeating: validPath, count: 32))
        #expect(throws: CommandProtocolError.frameTooLarge) { try CommandRequestCodec.encode(request) }
    }

    @Test(arguments: [
        "{\"version\":1,\"version\":1}", "{\"version\":1,\"\\u0076ersion\":1}",
        "[]", "{\"version\":1.0}", "{\"version\":1e0}", "{\"version\":true}",
        "{\"version\":2}", "{\"version\":1,\"future\":true}",
    ])
    func malformedOrUnsupportedMetadataIsRejected(_ text: String) {
        #expect(throws: CommandProtocolError.self) { try CommandRequestCodec.decode(Data(text.utf8)) }
    }

    @Test func wrongTypesMissingFieldsAndUnknownNestedMembersAreRejected() throws {
        let base = try CommandRequestCodec.encode(CommandOpenRequest(id: id, paths: ["/x"]))
        let object = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let unknownStdin: [String: Any] = ["byteCount": 0, "sha256": String(repeating: "a", count: 64), "future": 1]
        let corruptions: [[String: Any]] = [
            object.merging(["id": "not-a-uuid"]) { _, new in new },
            object.merging(["wait": 1]) { _, new in new },
            object.merging(["type": "execute"]) { _, new in new },
            object.merging(["paths": [1]]) { _, new in new },
            object.merging(["stdin": NSNull()]) { _, new in new },
            object.merging(["stdin": unknownStdin]) { _, new in new },
            object.filter { $0.key != "wait" },
        ]
        for corruption in corruptions {
            #expect(throws: CommandProtocolError.self) {
                try CommandRequestCodec.decode(JSONSerialization.data(withJSONObject: corruption))
            }
        }
        #expect(throws: CommandProtocolError.malformedMetadata) { try CommandRequestCodec.decode(Data([0xFF])) }
    }

    @Test(arguments: ["-1", "1.0", "1e0", "33554433", "999999999999999999999999999999"])
    func stdinCountMustBeABoundedCanonicalInteger(_ count: String) throws {
        let base = try CommandRequestCodec.encode(CommandOpenRequest(id: id, paths: []))
        let prefix = try #require(String(data: base, encoding: .utf8)).dropLast()
        let raw = Data((prefix + ",\"stdin\":{\"byteCount\":" + count
                + ",\"sha256\":\"" + String(repeating: "a", count: 64) + "\"}}").utf8)
        #expect(throws: CommandProtocolError.invalidStdinDescriptor) { try CommandRequestCodec.decode(raw) }
    }
}
