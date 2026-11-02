import FileCore
import Foundation
import Observation

public struct RecentFolderRootResolution: Sendable, Equatable {
    /// The lexical path the user selected, retained for the sidebar and session.
    public let lexicalURL: URL
    /// The physical target whose bookmark grants security-scoped access.
    public let accessURL: URL
}

@MainActor @Observable
public final class RecentFolderRoots {
    private struct StoredRoot: Codable {
        let bookmark: Data
        let lexicalURL: URL
    }

    public private(set) var roots: [URL] = []
    public var unresolvedBookmarkCount: Int {
        unresolved.count
    }

    private let preferences: FileTreePreferences
    private var bookmarks: [Data] = []
    private var unresolved: [Data] = []
    public let preservesUnavailableBookmarks: Bool
    public init(preferences: FileTreePreferences, preservesUnavailableBookmarks: Bool = false) {
        self.preservesUnavailableBookmarks = preservesUnavailableBookmarks
        self.preferences = preferences; reload()
    }

    public func record(_ url: URL) {
        let standardized = url.standardizedFileURL
        // Store access against the physical object, while retaining the lexical
        // URL as the user-facing label and tree root.
        let physical = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard let bookmark = try? physical.bookmarkData(options: .withSecurityScope) else { return }
        var updated = zip(roots, bookmarks).filter { $0.0 != standardized && !PhysicalFileIdentity.matches(
            $0.0,
            standardized
        ) }
        updated.insert((standardized, stored(bookmark: bookmark, lexicalURL: standardized)), at: 0)
        updated = Array(updated.prefix(10))
        roots = updated.map(\.0)
        bookmarks = updated.map(\.1)
        save()
    }

    public func resolve(_ url: URL) -> RecentFolderRootResolution? {
        guard let index = roots.firstIndex(where: { PhysicalFileIdentity.matches($0, url) })
        else { return nil }
        var stale = false
        let record = unpack(bookmarks[index], fallbackLexicalURL: roots[index])
        guard let resolved = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            if preservesUnavailableBookmarks {
                return nil
            }
            roots.remove(at: index)
            bookmarks.remove(at: index)
            save()
            return nil
        }
        let scope = FolderAccessScope(url: resolved)
        let standardized = resolved.standardizedFileURL
        let lexical = roots[index].standardizedFileURL
        // Keep a working symlink alias as the tree/display root. The scope
        // remains attached to the resolved bookmark target instead.
        var isDirectory = ObjCBool(false)
        let lexicalStillResolves = FileManager.default.fileExists(
            atPath: lexical.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue && PhysicalFileIdentity.matches(lexical, standardized)
        let reopenedRoot = lexicalStillResolves ? lexical : standardized
        if roots[index] != reopenedRoot {
            roots[index] = reopenedRoot
        }
        if stale, let refreshed = try? standardized.bookmarkData(options: .withSecurityScope) {
            bookmarks[index] = stored(bookmark: refreshed, lexicalURL: roots[index])
            save()
        }
        _ = scope
        return RecentFolderRootResolution(lexicalURL: reopenedRoot, accessURL: standardized)
    }

    public func clear() {
        roots = []; bookmarks = []; unresolved = []
        storeBookmarks([])
    }

    public func remap(from old: URL, to new: URL) {
        let oldComponents = old.standardizedFileURL.pathComponents
        var changed = false
        roots = roots.map { root in
            let components = root.standardizedFileURL.pathComponents
            guard components.starts(with: oldComponents) else { return root }
            changed = true
            let suffix = components.dropFirst(oldComponents.count).joined(separator: "/")
            return suffix.isEmpty
                ? new.standardizedFileURL
                : new.appendingPathComponent(suffix, isDirectory: true).standardizedFileURL
        }
        if changed {
            // A root move invalidates an old path bookmark. Keep it until the
            // replacement succeeds, so a bookmark generation failure cannot
            // discard the last valid access grant.
            for index in roots.indices {
                let physical = roots[index].resolvingSymlinksInPath().standardizedFileURL
                if let refreshed = try? physical.bookmarkData(options: .withSecurityScope) {
                    bookmarks[index] = stored(bookmark: refreshed, lexicalURL: roots[index])
                }
            }
            save()
        }
    }

    private func reload() {
        roots = []
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
                        roots.append(lexical); bookmarks.append(data)
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
            guard !seen.contains(where: { PhysicalFileIdentity.matches($0, lexical) }), roots.count < 10 else {
                changed = true
                continue
            }
            seen.append(lexical)
            roots.append(lexical)
            let scope = FolderAccessScope(url: resolved)
            if stale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope) {
                bookmarks.append(stored(bookmark: refreshed, lexicalURL: lexical))
                changed = true
            } else {
                bookmarks.append(data)
            }
            _ = scope
        }
        if changed {
            save()
        }
    }

    /// Refresh grants only for already-created descendants of the new owned
    /// installation. Outside or unresolved bookmarks remain byte-identical.
    public static func relocatedInstallationBookmarks(_ values: [Data],
                                                      map: (URL) throws -> URL?) throws -> [Data] {
        try values.map { data in
            let stored = try? JSONDecoder().decode(StoredRoot.self, from: data)
            var stale = false
            let old = stored?.lexicalURL ?? (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                                      relativeTo: nil, bookmarkDataIsStale: &stale))
            guard let old, let new = try map(old) else { return data }
            return try JSONEncoder().encode(StoredRoot(bookmark: new.bookmarkData(options: .withSecurityScope),
                                                       lexicalURL: new))
        }
    }

    private func save() {
        storeBookmarks(bookmarks + unresolved)
    }

    private func stored(bookmark: Data, lexicalURL: URL) -> Data {
        let record = StoredRoot(bookmark: bookmark, lexicalURL: lexicalURL)
        return (try? JSONEncoder().encode(record)) ?? bookmark
    }

    private func unpack(_ data: Data, fallbackLexicalURL: URL?) -> (bookmark: Data, lexicalURL: URL?) {
        if let record = try? JSONDecoder().decode(StoredRoot.self, from: data) {
            return (record.bookmark, record.lexicalURL)
        }
        return (data, fallbackLexicalURL)
    }

    private func storedBookmarks() -> [Data] {
        preferences.recentRootBookmarks()
    }

    private func storeBookmarks(_ bookmarks: [Data]) {
        preferences.storeRecentRootBookmarks(bookmarks)
    }
}

@MainActor private extension FileTreePreferences {
    func recentRootBookmarks() -> [Data] {
        store.recentRootBookmarks
    }

    func storeRecentRootBookmarks(_ bookmarks: [Data]) {
        store.recentRootBookmarks = bookmarks
    }
}
