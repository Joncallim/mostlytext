@testable import FileCore
import Foundation
import Testing

struct FileByteDecoderTests {
    @Test func emptyAndExactByteBudgetAreAccepted() throws {
        #expect(try FileByteDecoder.decode(Data(), maximumBytes: 0).text.isEmpty)
        let bytes = Data("日本語 👩🏽‍💻\r\nCR\rLF\n".utf8)
        let decoded = try FileByteDecoder.decode(bytes, maximumBytes: bytes.count)
        #expect(decoded.text == "日本語 👩🏽‍💻\r\nCR\rLF\n")
        #expect(decoded.metadata == .utf8Default)
    }

    @Test func admissionRejectsBytesBeforeInvalidEncodingIsInspected() {
        #expect(throws: FileByteDecodingError.invalidByteLimit) {
            try FileByteDecoder.decode(Data(), maximumBytes: -1)
        }
        #expect(throws: FileByteDecodingError.inputTooLarge(maximumBytes: 0)) {
            try FileByteDecoder.decode(Data([0xFF]), maximumBytes: 0)
        }
    }

    @Test func nonzeroDataIndicesDecodeWithoutShiftingTextOrDiagnostics() throws {
        var sliced = Data([0x00]) + Data("😀hello".utf8)
        sliced.removeFirst()
        #expect(sliced.startIndex != 0)
        #expect(try FileByteDecoder.decode(sliced, maximumBytes: 64).text == "😀hello")
        sliced.append(0xFF)
        do {
            _ = try FileByteDecoder.decode(sliced, maximumBytes: 64)
            Issue.record("Expected strict UTF-8 failure")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics.first?.byteOffset == Data("😀hello".utf8).count)
        }
    }

    @Test func preservesBOMAndEncodingMetadata() throws {
        let text = "# 日本語 😀\r\n"
        for (encoding, prefix, bom) in [
            (String.Encoding.utf8, [UInt8(0xEF), 0xBB, 0xBF], FileBOM.utf8),
            (.utf16LittleEndian, [0xFF, 0xFE], .utf16LittleEndian),
            (.utf16BigEndian, [0xFE, 0xFF], .utf16BigEndian),
        ] {
            let bytes = try Data(prefix) + #require(text.data(using: encoding))
            let result = try FileByteDecoder.decode(bytes, maximumBytes: 128)
            #expect(result.text == text)
            #expect(result.metadata == FileEncodingMetadata(encoding: encoding, bom: bom))
        }
    }

    @Test func explicitLegacyPolicyDoesNotBecomeAutomaticGuessing() throws {
        let text = "café\r\n"
        let bytes = try #require(text.data(using: .isoLatin1, allowLossyConversion: false))
        #expect(throws: FileStoreError.self) { try FileByteDecoder.decode(bytes, maximumBytes: 64) }
        let result = try FileByteDecoder.decode(bytes, maximumBytes: 64, policy: .explicit(.isoLatin1))
        #expect(result.text == text)
        #expect(result.metadata == FileEncodingMetadata(encoding: .isoLatin1, bom: .none))
        #expect(result.text.data(using: result.encoding, allowLossyConversion: false) == bytes)
    }

    @Test(arguments: [
        Data([0xC0, 0xAF]), Data([0xED, 0xA0, 0x80]), Data([0xF4, 0x90, 0x80, 0x80]),
        Data([0xFF, 0xFE, 0x00]), Data([0xFF, 0xFE, 0x00, 0xD8]), Data([0xFE, 0xFF, 0xDC, 0x00]),
    ])
    func malformedBytesNeverProduceReplacementText(bytes: Data) {
        #expect(throws: FileStoreError.self) { try FileByteDecoder.decode(bytes, maximumBytes: 64) }
    }

    @Test func decodedValueMatchesTheExistingEditorPolicy() throws {
        for bytes in [Data(), Data("# Title\r\n👩🏽‍💻\n".utf8), Data([0xEF, 0xBB, 0xBF, 0x61])] {
            let original = try FileStore().decode(bytes)
            #expect(try FileByteDecoder.decode(bytes, maximumBytes: 1024) == original)
        }
    }
}
