import FileCore
import Foundation

/// Persistent representation of an open tab session.
///
/// The schema is versioned so future epics can add fields without migration.
/// Unknown versions remain protected in storage and are reported by admission.
public struct WorkspaceSession: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var tabs: [TabRecord]
    public var activeTabID: UUID?

    public init(version: Int = currentVersion, tabs: [TabRecord] = [], activeTabID: UUID? = nil) {
        self.version = version
        self.tabs = tabs
        self.activeTabID = activeTabID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, tabs, activeTabID
    }

    /// A tab record that cannot be decoded (a field this build does not know, e.g. after a downgrade) costs
    /// that one tab, not the whole session: failing the entire decode meant no restore and an autosave that
    /// overwrote the file, orphaning every other tab's dirty recovery.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        tabs = try container.decode([LossyTabRecord].self, forKey: .tabs).compactMap(\.record)
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
    }

    private struct LossyTabRecord: Decodable {
        let record: TabRecord?

        init(from decoder: Decoder) throws {
            record = try? TabRecord(from: decoder)
        }
    }

    /// An empty session using the current schema version.
    public static var empty: WorkspaceSession {
        WorkspaceSession()
    }
}

/// One persisted tab.
public struct TabRecord: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, fileURL, untitledDocumentID, documentRecoveryEpoch, isPinned
        case cursorPosition, selectionLength, scrollOffset, previewLayout, previewMode, syntaxOverride
        case encoding, baseSHA256, folderRootBookmark, folderRootAlias
    }

    public var id: UUID
    public var fileURL: URL?
    public var untitledDocumentID: String?
    /// Exact recovery lifetime. Optional for sessions written before E18.
    public var documentRecoveryEpoch: UUID?
    public var isPinned: Bool

    /// The UTF-16 offset of the start of the editor selection. When
    /// `selectionLength` is zero this is the insertion point (caret).
    public var cursorPosition: Int?

    /// The number of UTF-16 code units selected. Together with `cursorPosition`
    /// this reconstructs the full `NSRange` on restore.
    public var selectionLength: Int?

    public var scrollOffset: Double?
    public var previewLayout: PreviewLayoutMode?
    /// The preview pane's display mode, or `nil` for the format's default.
    /// Optional so sessions written before EPIC-11 still decode.
    public var previewMode: PreviewMode?
    /// The tab's explicit Syntax Mode. Optional so sessions written before
    /// Slice 9d still decode.
    public var syntaxOverride: SyntaxModeOverride?
    /// Decoding metadata needed to interpret the restored text. Optional so
    /// sessions written before EPIC-11 still decode; absent metadata uses the
    /// documented default (UTF-8, no BOM). Raw bytes are never persisted.
    public var encoding: FileEncodingMetadata?
    /// SHA-256 of the file content this tab was last known to match on disk.
    /// A restored DIRTY tab whose file no longer hashes to this was changed
    /// outside the app while it was quit, and must come back as a conflict
    /// rather than silently adopting the new file as its baseline. Optional so
    /// older sessions still decode.
    public var baseSHA256: String?
    /// Optional so sessions written before the folder browser still decode.
    public var folderRootBookmark: Data?
    /// Lexical spelling paired with the physical security-scoped bookmark.
    public var folderRootAlias: URL?

    public init(
        id: UUID,
        fileURL: URL? = nil,
        untitledDocumentID: String? = nil,
        documentRecoveryEpoch: UUID? = nil,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        selectionLength: Int? = nil,
        scrollOffset: Double? = nil,
        previewLayout: PreviewLayoutMode? = nil,
        previewMode: PreviewMode? = nil,
        syntaxOverride: SyntaxModeOverride? = nil,
        encoding: FileEncodingMetadata? = nil,
        baseSHA256: String? = nil,
        folderRootBookmark: Data? = nil,
        folderRootAlias: URL? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.untitledDocumentID = untitledDocumentID
        self.documentRecoveryEpoch = documentRecoveryEpoch
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
        self.previewLayout = previewLayout
        self.previewMode = previewMode
        self.syntaxOverride = syntaxOverride
        self.encoding = encoding
        self.baseSHA256 = baseSHA256
        self.folderRootBookmark = folderRootBookmark
        self.folderRootAlias = folderRootAlias
    }
}

/// Abstraction over session persistence so `TabStore` can be tested with an
/// in-memory store and the real app can use a JSON file.
@MainActor
public protocol WorkspaceSessionStoring: Sendable {
    func loadSession() -> WorkspaceSession?
    func saveSession(_ session: WorkspaceSession)
    @discardableResult func saveSessionVerified(_ session: WorkspaceSession) -> Bool
}

public extension WorkspaceSessionStoring {
    /// A lifecycle boundary, unlike best-effort autosave. The caller can only
    /// retire a recovery redirect after the exact replacement session is
    /// readable from the canonical store.
    @discardableResult
    func saveSessionVerified(_ session: WorkspaceSession) -> Bool {
        saveSession(session)
        return loadSession() == session
    }
}

/// JSON file-backed session store.
///
/// Preserves unsupported/partial primary state. Ordinary autosave is best-effort;
/// verified lifecycle publication reports refusal/failure to its owner.
@MainActor
public struct WorkspaceSessionStore: WorkspaceSessionStoring {
    public static let defaultFileName = "session.json"

    let fileURL: URL
    var beforePublication: (@Sendable (URL) throws -> Void)?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            let directory = appSupport.appendingPathComponent("MacDown 2", isDirectory: true)
            self.fileURL = directory.appendingPathComponent(Self.defaultFileName)
        }
    }

    public func loadSession() -> WorkspaceSession? {
        let snapshot = readForAdmission()
        if !snapshot.admission.permitsPublication, let bytes = snapshot.bytes {
            preserveUnreadableSession(bytes)
        }
        return snapshot.admission.session
    }

    public func saveSession(_ session: WorkspaceSession) {
        _ = saveSessionVerified(session)
    }
}
