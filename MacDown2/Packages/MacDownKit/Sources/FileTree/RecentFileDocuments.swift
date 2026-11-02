import Darwin
import FileCore
import Foundation
import Observation

public struct RecentFileDocumentResolution: Sendable, Equatable {
    /// The lexical path the user opened, retained as the display label.
    public let lexicalURL: URL
    /// The physical target whose bookmark grants security-scoped access.
    public let accessURL: URL
}

/// Tracks recently opened individual documents (EPIC-22 issue #112, Slice
/// 6c), mirroring `RecentFolderRoots`' own bookmark/MRU/cap/staleness-refresh
/// shape rather than AppKit's own unused `NSDocumentController` recents
/// mechanism (§6.15's own design decision, made when Quick Open's own
/// per-window `WorkspaceFileIndex` was designed). Deliberately does not
/// mirror `remap(from:to:)` — that method exists to keep a folder root's own
/// bookmarks valid when the folder itself is renamed/moved as a unit via
/// this app's own Rename/Duplicate folder commands, which have no per-file
/// analog in the current feature set.
@MainActor @Observable
public final class RecentFileDocuments {
    /// Identifies the recorded file object itself, so an unrelated file that
    /// later appears at the old path is never mistaken for it (#183 F21). An
    /// inode plus creation time is stable across launches, unlike the volume
    /// and file-resource identifiers used for in-session equivalence.
    private struct Fingerprint: Codable, Equatable {
        let inode: UInt64
        let created: TimeInterval?

        init?(of url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            inode = UInt64(info.st_ino)
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            created = values?.creationDate?.timeIntervalSince1970
        }
    }

    private struct Unpacked {
        let bookmark: Data
        let lexicalURL: URL?
        let fingerprint: Fingerprint?
    }

    private struct StoredDocument: Codable {
        let bookmark: Data
        let lexicalURL: URL
        let fingerprint: Fingerprint?
    }

    public private(set) var documents: [URL] = []
    public var unresolvedBookmarkCount: Int {
        unresolved.count
    }

    private let preferences: FileTreePreferences
    private var bookmarks: [Data] = []
    private var unresolved: [Data] = []
    public let preservesUnavailableBookmarks: Bool

    public init(preferences: FileTreePreferences, preservesUnavailableBookmarks: Bool = false) {
        self.preservesUnavailableBookmarks = preservesUnavailableBookmarks
        self.preferences = preferences
        reload()
    }

    public func record(_ url: URL) {
        let standardized = url.standardizedFileURL
        let physical = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard let bookmark = try? physical.bookmarkData(options: .withSecurityScope) else { return }
        var updated = zip(documents, bookmarks).filter { $0.0 != standardized && !PhysicalFileIdentity.matches(
            $0.0,
            standardized
        ) }
        updated.insert(
            (standardized, stored(
                bookmark: bookmark,
                lexicalURL: standardized,
                fingerprint: Fingerprint(of: physical)
            )),
            at: 0
        )
        updated = Array(updated.prefix(10))
        documents = updated.map(\.0)
        bookmarks = updated.map(\.1)
        save()
        // A bookmark can resolve successfully (`resolve(_:)`'s own failure
        // path) even after its target file has been deleted or moved
        // outside this app's knowledge — non-sandboxed bookmark resolution
        // does not require the target to currently exist. Piggybacking the
        // pruning check on every real file open (rather than only at
        // launch) means a sibling recent entry that went stale mid-session
        // is cleaned up promptly instead of only on the next relaunch.
        pruneMissingFiles()
    }

    /// Saving replaces the file's inode and creation date, which would make the
    /// stored fingerprint reject the entry on the next open. Called after this
    /// app itself wrote `url`, so the entry follows the file it just published.
    public func noteWrite(of url: URL) {
        let standardized = url.standardizedFileURL
        let physical = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard let index = documents.firstIndex(where: { PhysicalFileIdentity.matches($0, standardized) }),
              let fingerprint = Fingerprint(of: physical),
              let bookmark = try? physical.bookmarkData(options: .withSecurityScope)
        else { return }
        bookmarks[index] = stored(bookmark: bookmark, lexicalURL: documents[index], fingerprint: fingerprint)
        save()
    }

    public func resolve(_ url: URL) -> RecentFileDocumentResolution? {
        guard let index = documents.firstIndex(where: { PhysicalFileIdentity.matches($0, url) })
        else { return nil }
        var stale = false
        let record = unpack(bookmarks[index], fallbackLexicalURL: documents[index])
        guard let resolved = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            if preservesUnavailableBookmarks {
                return nil
            }
            documents.remove(at: index)
            bookmarks.remove(at: index)
            save()
            return nil
        }
        let scope = FolderAccessScope(url: resolved)
        let standardized = resolved.standardizedFileURL
        // Bookmarks resolve path-first, so once an unrelated file sits at the
        // old path they resolve to *it*. Refuse it rather than open the wrong
        // file; the entry no longer refers to anything we can find.
        if let expected = record.fingerprint, Fingerprint(of: standardized) != expected {
            if preservesUnavailableBookmarks {
                return nil
            }
            documents.remove(at: index)
            bookmarks.remove(at: index)
            save()
            return nil
        }
        // The stored lexical path is only a display alias. Keep it while it
        // still identifies the bookmarked object; otherwise (the file moved and
        // an unrelated file may now sit at the old path) adopt the resolved
        // identity deliberately — `RecentFolderRoots.resolve`'s own rule (#183 F21).
        let lexical = documents[index].standardizedFileURL
        let lexicalStillIdentifiesIt = FileManager.default.fileExists(atPath: lexical.path)
            && PhysicalFileIdentity.matches(lexical, standardized)
        let reopened = lexicalStillIdentifiesIt ? lexical : standardized
        let changedAlias = documents[index] != reopened
        if changedAlias {
            documents[index] = reopened
        }
        if stale, let refreshed = try? standardized.bookmarkData(options: .withSecurityScope) {
            bookmarks[index] = stored(bookmark: refreshed, lexicalURL: reopened, fingerprint: record.fingerprint)
            save()
        } else if changedAlias {
            bookmarks[index] = stored(bookmark: record.bookmark, lexicalURL: reopened, fingerprint: record.fingerprint)
            save()
        }
        _ = scope
        return RecentFileDocumentResolution(lexicalURL: reopened, accessURL: standardized)
    }

    public func clear() {
        documents = []; bookmarks = []; unresolved = []
        storeBookmarks([])
    }

    /// Root-relative paths (matching `TextSearch.IndexedPath.relativePath`'s
    /// own `/`-separated, no-leading-slash format) of the recently opened
    /// documents that fall within `root` — issue #112's "Recent-file
    /// history feeds Quick Open ranking" requirement. Only a document
    /// actually inside the folder a given `WorkspaceFileIndex` was built
    /// from can ever appear in that index's own results, so this filters
    /// down to those before Quick Open sees them, rather than exposing
    /// every recent document across every folder ever opened. Deliberately
    /// returns plain strings, not a `FileTree`/`TextSearch`-specific type —
    /// `RecentFileDocuments` has no reason to depend on either package just
    /// to answer this.
    public func relativePaths(under root: URL) -> Set<String> {
        let rootPath = root.standardizedFileURL.path
        var result: Set<String> = []
        for document in documents {
            let documentPath = document.standardizedFileURL.path
            guard documentPath.hasPrefix(rootPath + "/") else { continue }
            result.insert(String(documentPath.dropFirst(rootPath.count + 1)))
        }
        return result
    }

    /// Drops any entry whose file no longer exists on disk. Issue #112's own
    /// words: "Add Open Recent File... with missing-path pruning". Public
    /// (not just called internally) so a caller who wants an up-to-the-
    /// moment check — before showing UI built from `documents`, for
    /// instance — can force one; `reload()` (app launch) and `record(_:)`
    /// (every real file open) already call it on their own, since those are
    /// the points at which this app naturally has an opportunity to notice
    /// a sibling entry has gone stale, unlike a folder root, which
    /// `RecentFolderRoots.resolve(_:)` re-validates constantly during
    /// ordinary browsing.
    public func pruneMissingFiles() {
        var survivors: [(URL, Data)] = []
        var changed = false
        for (url, bookmark) in zip(documents, bookmarks) {
            if FileManager.default.fileExists(atPath: url.path) {
                survivors.append((url, bookmark))
            } else if let moved = movedFile(for: bookmark) {
                // The lexical path vanished but the bookmark still finds the
                // file (it was moved/renamed): keep it under its new path.
                let record = unpack(bookmark, fallbackLexicalURL: nil)
                survivors.append((
                    moved,
                    stored(bookmark: record.bookmark, lexicalURL: moved, fingerprint: record.fingerprint)
                ))
                changed = true
            } else if preservesUnavailableBookmarks {
                var info = stat()
                if stat(url.path, &info) != 0, errno != ENOENT, errno != ENOTDIR {
                    survivors.append((url, bookmark))
                }
            }
        }
        guard changed || survivors.count != documents.count else { return }
        documents = survivors.map(\.0)
        bookmarks = survivors.map(\.1)
        save()
    }

    private func reload() {
        documents = []
        bookmarks = []
        unresolved = []
        var changed = false
        var seen: [URL] = []
        for data in storedBookmarks() {
            let record = unpack(data, fallbackLexicalURL: nil)
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                if preservesUnavailableBookmarks {
                    if let lexical = record.lexicalURL {
                        documents.append(lexical); bookmarks.append(data)
                    } else {
                        unresolved.append(data)
                    }
                } else {
                    changed = true
                }
                continue
            }
            let resolved = url.standardizedFileURL
            let lexical = record.lexicalURL ?? resolved
            guard !seen.contains(where: { PhysicalFileIdentity.matches($0, lexical) }), documents.count < 10 else {
                changed = true
                continue
            }
            seen.append(lexical)
            documents.append(lexical)
            let scope = FolderAccessScope(url: resolved)
            if stale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope) {
                bookmarks.append(stored(bookmark: refreshed, lexicalURL: lexical, fingerprint: record.fingerprint))
                changed = true
            } else {
                bookmarks.append(data)
            }
            _ = scope
        }
        if changed {
            save()
        }
        pruneMissingFiles()
    }

    public static func relocatedInstallationBookmarks(_ values: [Data],
                                                      map: (URL) throws -> URL?) throws -> [Data] {
        try values.map { data in
            let stored = try? JSONDecoder().decode(StoredDocument.self, from: data)
            var stale = false
            let old = stored?.lexicalURL ?? (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                                      relativeTo: nil, bookmarkDataIsStale: &stale))
            guard let old, let new = try map(old) else { return data }
            return try JSONEncoder().encode(StoredDocument(bookmark: new.bookmarkData(options: .withSecurityScope),
                                                           lexicalURL: new, fingerprint: Fingerprint(of: new)))
        }
    }

    private func save() {
        storeBookmarks(bookmarks + unresolved)
    }

    /// Where a bookmark currently finds its file, if that file exists.
    private func movedFile(for data: Data) -> URL? {
        var stale = false
        let record = unpack(data, fallbackLexicalURL: nil)
        guard let url = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path),
              record.fingerprint == nil || Fingerprint(of: standardized) == record.fingerprint
        else { return nil }
        return standardized
    }

    private func stored(bookmark: Data, lexicalURL: URL, fingerprint: Fingerprint?) -> Data {
        let record = StoredDocument(bookmark: bookmark, lexicalURL: lexicalURL, fingerprint: fingerprint)
        return (try? JSONEncoder().encode(record)) ?? bookmark
    }

    private func unpack(_ data: Data, fallbackLexicalURL: URL?) -> Unpacked {
        if let record = try? JSONDecoder().decode(StoredDocument.self, from: data) {
            return Unpacked(bookmark: record.bookmark, lexicalURL: record.lexicalURL, fingerprint: record.fingerprint)
        }
        return Unpacked(bookmark: data, lexicalURL: fallbackLexicalURL, fingerprint: nil)
    }

    private func storedBookmarks() -> [Data] {
        preferences.recentFileBookmarks()
    }

    private func storeBookmarks(_ bookmarks: [Data]) {
        preferences.storeRecentFileBookmarks(bookmarks)
    }
}

@MainActor private extension FileTreePreferences {
    func recentFileBookmarks() -> [Data] {
        store.recentFileBookmarks
    }

    func storeRecentFileBookmarks(_ bookmarks: [Data]) {
        store.recentFileBookmarks = bookmarks
    }
}
