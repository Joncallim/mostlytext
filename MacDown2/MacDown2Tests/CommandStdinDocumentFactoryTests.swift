import CommandBridge
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

struct CommandStdinDocumentFactoryTests {
    struct Sample: Sendable {
        let bytes: Data
        let text: String
        let bom: FileBOM
    }

    private static let validSources: [Sample] = [
        Sample(bytes: Data(), text: "", bom: .none),
        Sample(bytes: Data([0xEF, 0xBB, 0xBF]), text: "", bom: .utf8),
        Sample(bytes: Data("alpha\r\nbeta\rgamma\n".utf8), text: "alpha\r\nbeta\rgamma\n", bom: .none),
        Sample(bytes: Data([0xEF, 0xBB, 0xBF]) + Data("\u{FEFF}author\r\n".utf8),
               text: "\u{FEFF}author\r\n", bom: .utf8),
    ]

    @Test(arguments: validSources)
    func exactSourceGetsAManagedDirtyRecoveryLifetime(_ sample: Sample) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let document = try await CommandStdinDocumentFactory.prepare(sample.bytes, recoveryBuffer: buffer)
        #expect(document.fileURL == nil)
        #expect(document.state == .dirty)
        #expect(document.format.id == "markdown")
        #expect(document.encoding.encodingRawValue == String.Encoding.utf8.rawValue)
        #expect(document.encoding.bom == sample.bom)
        #expect(document.text.utf8.elementsEqual(sample.text.utf8))
        #expect(document.mutationGeneration > 0)
        let recovered = try #require(try await buffer.load(for: document.id, epoch: document.recoveryEpoch))
        #expect(recovered.utf8.elementsEqual(sample.text.utf8))
        let restarted = RecoveryBuffer(recoveryDirectory: directory)
        let afterRestart = try #require(try await restarted.load(for: document.id, epoch: document.recoveryEpoch))
        #expect(afterRestart.utf8.elementsEqual(sample.text.utf8))
    }

    @Test(arguments: [Data([0xFF, 0xFE]), Data([0xC0, 0x80]), Data([0xED, 0xA0, 0x80])])
    func invalidUTF8CreatesNoRecoveryState(_ bytes: Data) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        await #expect(throws: (any Error).self) {
            try await CommandStdinDocumentFactory.prepare(bytes, recoveryBuffer: buffer)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func oversizedInputIsRefusedBeforeRecoveryPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let bytes = Data(repeating: 0x61, count: CommandProtocol.maximumStdinBytes + 1)
        await #expect(throws: FileByteDecodingError.inputTooLarge(maximumBytes: CommandProtocol.maximumStdinBytes)) {
            try await CommandStdinDocumentFactory.prepare(bytes, recoveryBuffer: buffer)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test @MainActor func emptySourceRestoresWithItsExactSessionEpoch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recoveryURL = root.appendingPathComponent("recovery")
        let document = try await CommandStdinDocumentFactory.prepare(Data(),
                                                                     recoveryBuffer: RecoveryBuffer(
                                                                         recoveryDirectory: recoveryURL
                                                                     ))
        let record = TabRecord(id: UUID(), fileURL: nil, untitledDocumentID: document.id,
                               documentRecoveryEpoch: document.recoveryEpoch, encoding: document.encoding)
        let sessionURL = root.appendingPathComponent("session.json")
        let store = WorkspaceSessionStore(fileURL: sessionURL)
        #expect(store.saveSessionVerified(WorkspaceSession(tabs: [record], activeTabID: record.id)))
        let restarted = TabStore(sessionStore: WorkspaceSessionStore(fileURL: sessionURL),
                                 recoveryBuffer: RecoveryBuffer(recoveryDirectory: recoveryURL))
        await restarted.restoreSessionIfNeeded()
        let restored = try #require(restarted.activeTab?.document)
        #expect(restored.id == document.id)
        #expect(restored.recoveryEpoch == document.recoveryEpoch)
        #expect(restored.state == .dirty)
        #expect(restored.text.isEmpty)
    }

    @Test func unavailableRecoveryDoesNotReturnAnAdmittedDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("blocked")
        let sentinel = Data("keep this file".utf8)
        try sentinel.write(to: directory)
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        await #expect(throws: (any Error).self) {
            try await CommandStdinDocumentFactory.prepare(Data("authored source".utf8), recoveryBuffer: buffer)
        }
        #expect(try Data(contentsOf: directory) == sentinel)
    }
}
