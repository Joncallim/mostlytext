import Darwin
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
    let beforeMovedCandidateRead: (@Sendable (URL) -> Void)?

    func snapshot(_ url: URL) throws(FileStoreError) -> FileSnapshot {
        try store.readSnapshot(from: url, decoding: policy)
    }
}

struct DocumentFileProbe: DocumentFileProbing, Sendable {
    let fileStore: FileStore
    private let beforeMovedCandidateRead: (@Sendable (URL) -> Void)?

    init(fileStore: FileStore = FileStore(), beforeMovedCandidateRead: (@Sendable (URL) -> Void)? = nil) {
        self.fileStore = fileStore
        self.beforeMovedCandidateRead = beforeMovedCandidateRead
    }

    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        decoding: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        let store = fileStore
        let beforeMovedCandidateRead = beforeMovedCandidateRead
        return await Task.detached(priority: .utility) {
            Self.observeSynchronously(
                expectedURL: expectedURL.standardizedFileURL,
                priorFileObjectID: priorFileObjectID,
                reader: SnapshotReader(
                    store: store,
                    policy: decoding,
                    beforeMovedCandidateRead: beforeMovedCandidateRead
                )
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
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { return .unavailable(classifyParentReadFailure(errno)) }
        guard let stream = fdopendir(descriptor) else {
            let failure = errno
            Darwin.close(descriptor)
            return .unavailable(classifyParentReadFailure(failure))
        }
        defer { closedir(stream) }

        var matches: [FileSnapshot] = []
        while !Task.isCancelled {
            // Metadata/read failures can set errno too. Only this readdir's
            // error may turn the end of enumeration into a parent failure.
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 {
                    return .unavailable(classifyParentReadFailure(errno))
                }
                break
            }
            guard let snapshot = movedCandidate(
                entry, descriptor: descriptor, matching: objectID,
                excluding: expectedURL, reader: reader
            ) else { continue }
            matches.append(snapshot)
            if matches.count > 1 {
                return .ambiguous
            }
        }
        guard let snapshot = matches.first else { return .none }
        return .one(snapshot)
    }

    private static func movedCandidate(
        _ entry: UnsafeMutablePointer<dirent>, descriptor: Int32,
        matching objectID: PhysicalFileIdentity.FileObjectID, excluding expectedURL: URL,
        reader: SnapshotReader
    ) -> FileSnapshot? {
        let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
        return withUnsafePointer(to: &entry.pointee.d_name) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { name in
                var info = stat()
                guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                      matches(info, objectID: objectID) else { return nil }
                // Unrelated siblings never allocate/canonicalize a URL or read
                // document bytes. The opened snapshot must still be that file.
                let url = URL(
                    fileURLWithFileSystemRepresentation: name,
                    isDirectory: false,
                    relativeTo: expectedURL.deletingLastPathComponent()
                )
                guard url.standardizedFileURL != expectedURL else { return nil }
                reader.beforeMovedCandidateRead?(url)
                guard let snapshot = try? reader.snapshot(url), snapshot.revision.fileObjectID == objectID,
                      fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                      matches(info, objectID: objectID) else { return nil }
                return snapshot
            }
        }
    }

    private static func matches(_ info: stat, objectID: PhysicalFileIdentity.FileObjectID) -> Bool {
        info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && String(info.st_dev) == objectID.volume && String(info.st_ino) == objectID.file
    }

    private static func classifyReadFailure(_ error: Error) -> FileBackingIssue {
        let nsError = error as NSError
        if nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        return .readFailed(error.localizedDescription)
    }

    private static func classifyParentReadFailure(_ code: Int32) -> FileBackingIssue {
        switch code {
        case EACCES, EPERM:
            .permissionDenied
        default:
            .parentUnavailable
        }
    }
}
