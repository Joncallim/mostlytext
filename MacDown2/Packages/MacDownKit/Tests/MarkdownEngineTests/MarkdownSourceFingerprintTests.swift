import CryptoKit
import Foundation
@testable import MarkdownEngine
import Testing

struct MarkdownSourceFingerprintTests {
    @Test(arguments: [0, 1, 65535, 65536, 65537])
    func exactBytesAgreeWithTheDigestOracleAcrossChunkBoundaries(count: Int) {
        let source = String(repeating: "a", count: count) + "ÅÅ𝛼"
        let expected = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let native = MarkdownSourceFingerprint.sha256(source)
        let bridged = MarkdownSourceFingerprint.sha256((source as NSString) as String)
        #expect(native == expected)
        #expect(bridged == expected)
    }

    @Test func standardEmptyAndASCIIHashVectorsAreStable() {
        #expect(MarkdownSourceFingerprint.sha256("") ==
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(MarkdownSourceFingerprint.sha256("abc") ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
