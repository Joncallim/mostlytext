@testable import FileCore
import Foundation
import Testing

/// EPIC-11 §3.2 — BOM/encoding metadata round trips through FileStore and
/// FileDocument.
@Suite("FileEncodingMetadata")
struct FileEncodingMetadataTests {
    private func temporaryFile(name: String = "fixture") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    @Test func utf8BOMRoundTrip() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try store.write("héllo", to: url, bom: .utf8)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == "héllo")
        #expect(snapshot.bom == .utf8)
        #expect(snapshot.encoding == .utf8)
        #expect(snapshot.encodingMetadata == FileEncodingMetadata(encoding: .utf8, bom: .utf8))
    }

    @Test func utf16LittleEndianBOMRoundTrip() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try store.write("héllo", to: url, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == "héllo")
        #expect(snapshot.bom == .utf16LittleEndian)
        #expect(snapshot.encoding == .utf16LittleEndian)
    }

    @Test func utf16BigEndianBOMRoundTrip() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try store.write("héllo", to: url, encoding: .utf16BigEndian, bom: .utf16BigEndian)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == "héllo")
        #expect(snapshot.bom == .utf16BigEndian)
        #expect(snapshot.encoding == .utf16BigEndian)
    }

    @Test func rawBytesAreNotRetainedInSnapshot() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try store.write("content", to: url)
        let snapshot = try store.readSnapshot(from: url)

        // FileSnapshot must not expose raw bytes: sha256 (a String) is the
        // only byte-derived identity it carries.
        #expect(snapshot.revision.sha256.isEmpty == false)
        #expect(snapshot.text == "content")
    }

    @Test func ordinaryWriteWithoutBOMRoundTripsAsNone() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try store.write("plain", to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.bom == .none)
        #expect(snapshot.encoding == .utf8)
    }

    @Test func encodingMetadataIsCodable() throws {
        let metadata = FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(FileEncodingMetadata.self, from: data)
        #expect(decoded == metadata)
    }
}

/// EPIC-11 §3.2 — FileDocument carries encoding metadata through load, edit,
/// ordinary save, and Save As.
@Suite("FileDocumentEncodingRoundTrip")
struct FileDocumentEncodingRoundTripTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func loadCapturesSnapshotEncoding() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url, bom: .utf8)

        let document = FileDocument(fileURL: url, fileStore: store)
        let loaded = try document.load()

        #expect(loaded.encoding == FileEncodingMetadata(encoding: .utf8, bom: .utf8))
    }

    @Test func editedPreservesEncoding() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)

        var document = try FileDocument(fileURL: url, fileStore: store).load()
        document = document.edited(text: "{\"a\":2}")
        document = document.edited(text: "{\"a\":3}")

        #expect(document.encoding.bom == .utf16LittleEndian)
    }

    @Test func ordinarySavePreservesEncodingAndBOM() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)

        var document = try FileDocument(fileURL: url, fileStore: store).load()
        document = document.edited(text: "{\"a\":1,\"b\":2}")
        let saved = try document.save()

        #expect(saved.encoding.bom == .utf16LittleEndian)
        let reread = try store.readSnapshot(from: url)
        #expect(reread.bom == .utf16LittleEndian)
        #expect(reread.text == "{\"a\":1,\"b\":2}")
    }

    @Test func saveAsInheritsSourceEncodingByDefault() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json")
        let destination = directory.appendingPathComponent("dest.json")
        _ = try store.write("{\"a\":1}", to: source, bom: .utf8)

        var document = try FileDocument(fileURL: source, fileStore: store).load()
        document = document.edited(text: "{\"a\":2}")
        let savedAs = try document.saveAs(destination)

        #expect(savedAs.encoding.bom == .utf8)
        #expect(try store.readSnapshot(from: destination).bom == .utf8)
    }

    @Test func saveAsExplicitOverrideBecomesMetadataOnlyAfterPublication() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json")
        let destination = directory.appendingPathComponent("dest.json")
        _ = try store.write("{\"a\":1}", to: source)

        let document = try FileDocument(fileURL: source, fileStore: store).load()
        let override = FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        let savedAs = try document.saveAs(destination, encodingOverride: override)

        #expect(savedAs.encoding == override)
        let reread = try store.readSnapshot(from: destination)
        #expect(reread.bom == .utf16LittleEndian)
        #expect(reread.text == "{\"a\":1}")
    }

    @Test func renamedPreservesEncoding() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("a.json")
        let destination = directory.appendingPathComponent("b.json")
        _ = try store.write("{\"a\":1}", to: source, encoding: .utf16BigEndian, bom: .utf16BigEndian)

        let document = try FileDocument(fileURL: source, fileStore: store).load()
        let renamed = document.renamed(to: destination)

        #expect(renamed.encoding.bom == .utf16BigEndian)
    }

    @Test func untitledDocumentsDefaultToUTF8WithoutBOM() {
        let document = FileDocument()
        #expect(document.encoding == .utf8Default)
    }

    @Test func updatingTextPreservesEncoding() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url, bom: .utf8)

        let document = try FileDocument(fileURL: url, fileStore: store).load()
        let updated = document.updatingText("{\"b\":2}")

        #expect(updated.encoding.bom == .utf8)
    }

    @Test func externalReloadReplacesEncodingTogetherWithText() throws {
        let store = FileStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url)

        let document = try FileDocument(fileURL: url, fileStore: store).load()
        // External writer replaces the file in UTF-16 LE with BOM.
        _ = try store.write("{\"a\":2}", to: url, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        let snapshot = try store.readSnapshot(from: url)
        let reconciliation = document.reconcilingExternalSnapshot(snapshot)

        #expect(reconciliation.disposition == .reloaded)
        #expect(reconciliation.document.encoding.bom == .utf16LittleEndian)
        #expect(reconciliation.document.text == "{\"a\":2}")
    }
}

/// EPIC-11 §3.2 — malformed byte payloads produce one diagnostic with the
/// first invalid byte sequence's zero-based offset and no text snapshot.
@Suite("FileStoreMalformedEncodingPayload")
struct FileStoreMalformedEncodingPayloadTests {
    private func writeRawBytes(_ bytes: [UInt8], to url: URL) throws {
        try Data(bytes).write(to: url)
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("broken.txt")
    }

    @Test func strayContinuationByteReportsItsOffset() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeRawBytes([0x61, 0x80, 0x62], to: url)

        let store = FileStore()
        #expect(throws: FileStoreError.self) {
            _ = try store.readSnapshot(from: url)
        }
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].byteOffset == 1)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func truncatedMultiByteSequenceReportsLeadByteOffset() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // 0xC3 starts a 2-byte sequence but the file ends.
        try writeRawBytes([0x61, 0xC3], to: url)

        let store = FileStore()
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics[0].byteOffset == 1)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func overlongEncodingIsRejected() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // 0xC0 0x80 is an overlong encoding of NUL.
        try writeRawBytes([0x41, 0xC0, 0x80, 0x42], to: url)

        let store = FileStore()
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics[0].byteOffset == 1)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func surrogateCodePointIsRejected() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // ED A0 80 encodes U+D800 (a surrogate), invalid in UTF-8.
        try writeRawBytes([0x41, 0xED, 0xA0, 0x80, 0x42], to: url)

        let store = FileStore()
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics[0].byteOffset == 1)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func invalidSequenceAfterUTF8BOMReportsOffsetRelativeToFile() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // BOM (3 bytes) then a stray continuation at byte offset 4.
        try writeRawBytes([0xEF, 0xBB, 0xBF, 0x61, 0x80], to: url)

        let store = FileStore()
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            #expect(diagnostics[0].byteOffset == 4)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func utf16UnpairedSurrogateReportsUnitOffset() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // UTF-16 LE with BOM: 'a', then a lone high surrogate D800, then 'b'.
        let bytes: [UInt8] = [0xFF, 0xFE, 0x61, 0x00, 0x00, 0xD8, 0x62, 0x00]
        try writeRawBytes(bytes, to: url)

        let store = FileStore()
        do {
            _ = try store.readSnapshot(from: url)
            Issue.record("Expected decodingFailed")
        } catch let FileStoreError.decodingFailed(diagnostics) {
            // Offset 4 = after BOM (2) + 'a' (2).
            #expect(diagnostics[0].byteOffset == 4)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func malformedFileLeavesPriorDocumentStateUntouched() throws {
        let store = FileStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")

        _ = try store.write("{\"a\":1}", to: url)
        var document = try FileDocument(fileURL: url, fileStore: store).load()
        document = document.edited(text: "{\"a\":2}")

        try Data([0x7B, 0x80]).write(to: url) // corrupt the file

        let snapshot = try? store.readSnapshot(from: url)
        #expect(snapshot == nil)

        // The prior in-memory document and its dirty state are unchanged.
        #expect(document.text == "{\"a\":2}")
        #expect(document.state == .dirty)
        #expect(document.encoding == .utf8Default)
    }
}

/// EPIC-11 §3.2 — encoding precedence: explicit override > detected/source
/// metadata; session restore persists metadata and defaults for legacy
/// records.
@Suite("FileEncodingPrecedence")
struct FileEncodingPrecedenceTests {
    @Test func explicitOverrideBeatsSourceMetadata() throws {
        let store = FileStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json")
        let destination = directory.appendingPathComponent("dest.json")
        _ = try store.write("{\"a\":1}", to: source, bom: .utf8)

        let document = try FileDocument(fileURL: source, fileStore: store).load()
        let override = FileEncodingMetadata(encoding: .utf16BigEndian, bom: .utf16BigEndian)
        let savedAs = try document.saveAs(destination, encodingOverride: override)

        #expect(savedAs.encoding == override)
        #expect(try store.readSnapshot(from: destination).encoding == .utf16BigEndian)
    }
}
