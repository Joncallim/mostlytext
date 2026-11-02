import Foundation

public enum DocumentFileObservation: Sendable, Equatable {
    case available(FileSnapshot)
    case moved(FileSnapshot)
    case missing(URL)
    case unavailable(URL, FileBackingIssue)
}

/// Immutable monitor metadata travels with every emitted observation. The
/// controller uses both generations because a binding can remain the same
/// while an older detached probe is superseded by a newer signal.
public struct DocumentFileObservationContext: Sendable, Equatable {
    public let observation: DocumentFileObservation
    public let bindingGeneration: UInt
    public let requestGeneration: UInt
    public let expectedURL: URL

    public init(
        observation: DocumentFileObservation,
        bindingGeneration: UInt,
        requestGeneration: UInt,
        expectedURL: URL
    ) {
        self.observation = observation
        self.bindingGeneration = bindingGeneration
        self.requestGeneration = requestGeneration
        self.expectedURL = expectedURL
    }
}

protocol DocumentFileProbing: Sendable {
    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        decoding: FileDecodingPolicy
    ) async -> DocumentFileObservation
}

struct SnapshotReader: Sendable {
    let store: FileStore
    let policy: FileDecodingPolicy

    func snapshot(_ url: URL) throws(FileStoreError) -> FileSnapshot {
        try store.readSnapshot(from: url, decoding: policy)
    }
}

struct DocumentFileProbe: DocumentFileProbing, Sendable {
    let fileStore: FileStore

    init(fileStore: FileStore = FileStore()) {
        self.fileStore = fileStore
    }

    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        decoding: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        let store = fileStore
        return await Task.detached(priority: .utility) {
            Self.observeSynchronously(
                expectedURL: expectedURL.standardizedFileURL,
                priorFileObjectID: priorFileObjectID,
                reader: SnapshotReader(store: store, policy: decoding)
            )
        }.value
    }

    private static func observeSynchronously(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        reader: SnapshotReader
    ) -> DocumentFileObservation {
        do {
            // The expected path holds a readable file: that IS the document, even
            // if the object behind it changed (an editor's atomic save, a
            // backup-by-rename — `perl -pi.bak`, Emacs — or a deleted-and-recreated
            // file). A sibling that carries the OLD object (`foo.md.bak`) is a
            // backup, not where the document went: rebinding to it would retitle
            // the window and make the next Save write into the backup. A move is
            // only inferred when the expected path is gone.
            return try .available(reader.snapshot(expectedURL))
        } catch {
            return observation(
                after: error,
                expectedURL: expectedURL,
                priorFileObjectID: priorFileObjectID,
                reader: reader
            )
        }
    }

    private static func observation(
        after error: FileStoreError,
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        reader: SnapshotReader
    ) -> DocumentFileObservation {
        switch error {
        case .fileMissing:
            missingOrMoved(
                expectedURL: expectedURL,
                priorFileObjectID: priorFileObjectID,
                reader: reader
            )
        case .permissionDenied:
            .unavailable(expectedURL, .permissionDenied)
        case .notRegularFile:
            .unavailable(expectedURL, .notRegularFile)
        case let .readFailed(underlying):
            .unavailable(expectedURL, classifyReadFailure(underlying))
        case .invalidURL, .encodingDetectionFailed, .textNotRepresentable, .fileChangedDuringRead, .writeFailed,
             .decodingFailed, .conditionalPublicationRecoveryRequired:
            .unavailable(expectedURL, .readFailed(String(describing: error)))
        }
    }

    private enum MoveSearchResult {
        case none
        case one(FileSnapshot)
        case ambiguous
        case unavailable(FileBackingIssue)
    }

    private static func missingOrMoved(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        reader: SnapshotReader
    ) -> DocumentFileObservation {
        guard let priorFileObjectID else { return .missing(expectedURL) }
        switch findMovedSnapshot(
            in: expectedURL.deletingLastPathComponent(),
            matching: priorFileObjectID,
            excluding: expectedURL,
            reader: reader
        ) {
        case let .one(snapshot): return .moved(snapshot)
        case .ambiguous: return .unavailable(expectedURL, .ambiguousMove)
        case let .unavailable(issue): return .unavailable(expectedURL, issue)
        case .none: return .missing(expectedURL)
        }
    }

    private static func findMovedSnapshot(
        in directory: URL,
        matching objectID: PhysicalFileIdentity.FileObjectID,
        excluding expectedURL: URL,
        reader: SnapshotReader
    ) -> MoveSearchResult {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .fileResourceIdentifierKey,
                    .volumeIdentifierKey,
                    .isRegularFileKey,
                ],
                options: []
            )
        } catch {
            return .unavailable(classifyParentReadFailure(error))
        }

        var matches: [FileSnapshot] = []
        for url in urls where url.standardizedFileURL != expectedURL.standardizedFileURL {
            // Directory enumeration prefetched the cheap identity metadata.
            // Only a candidate with the exact volume/file identity warrants a
            // full read and SHA-256 calculation; large sibling directories
            // must never hash every Markdown file just to detect a move.
            guard !Task.isCancelled,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let volume = attributes[.systemNumber] as? NSNumber,
                  let file = attributes[.systemFileNumber] as? NSNumber,
                  PhysicalFileIdentity.FileObjectID(
                      volume: volume.stringValue,
                      file: file.stringValue
                  ) == objectID,
                  let snapshot = try? reader.snapshot(url)
            else { continue }
            matches.append(snapshot)
            if matches.count > 1 {
                return .ambiguous
            }
        }
        guard let snapshot = matches.first else { return .none }
        return .one(snapshot)
    }

    private static func classifyReadFailure(_ error: Error) -> FileBackingIssue {
        let nsError = error as NSError
        if nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        return .readFailed(error.localizedDescription)
    }

    private static func classifyParentReadFailure(_ error: Error) -> FileBackingIssue {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return .parentUnavailable
        case NSFileReadNoPermissionError:
            return .permissionDenied
        default:
            return .parentUnavailable
        }
    }
}
