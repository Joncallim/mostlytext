import FileCore
import Foundation

/// The recursive walk itself, isolated from the actor so it can run inside
/// `Task.detached` without capturing actor state, and so its symlink-loop
/// safety (new; `FileTree`'s own traversal is single-level/lazy and has no
/// equivalent guard — see `planning/epic-22-implementation.md` §2.1) is
/// independently testable.
///
/// Deliberately does not depend on `FileTree`'s `DirectoryReading`/
/// `FileSystemDirectoryReader`/`DirectoryEntry` (single-level-listing types
/// designed for the sidebar's lazy, expand-on-click model) — `TextSearch`
/// depends only on `FileCore` + Foundation (architecture doc §5.1), so this
/// is a small, deliberate, local duplication of "list one directory's
/// entries with the resource keys a recursive walk needs," not a shared
/// primitive.
struct DirectoryWalker: Sendable {
    private enum WalkFailure: Error {
        case directoryIdentityUnavailable
    }

    private let listChildren: @Sendable (URL) throws -> [URL]

    init() {
        listChildren = { directory in
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: []
            )
        }
    }

    /// Test seam for a directory that stops being enumerable during a walk.
    init(listChildren: @escaping @Sendable (URL) throws -> [URL]) {
        self.listChildren = listChildren
    }

    /// The inputs that stay constant across every recursive call, bundled
    /// so the recursive `walk` method takes one value instead of two
    /// separate parameters (SwiftLint's `function_parameter_count` limit).
    private struct WalkContext {
        let root: URL
        let excludedDirectoryNames: Set<String>
        let maximumPaths: Int
        let maximumDirectories: Int
    }

    /// Mutable walk bookkeeping: the ancestor chain (symlink-loop guard) and how many directories were entered.
    private struct WalkState {
        var visited: Set<PhysicalFileIdentity.FileObjectID> = []
        var directoriesEntered = 0
    }

    /// A link such as `docs -> /` is followed on purpose (a linked directory is part of the project), so the
    /// walk needs an upper bound instead: past this many entries it stops rather than indexing a whole disk.
    static let defaultMaximumPaths = 250_000

    /// The loop guard only covers the ancestor chain, so a directory reached through N links is walked N times and
    /// a tree of links to empty directories grows multiplicatively without ever adding a path. Directory entries
    /// are budgeted too.
    static let defaultMaximumDirectories = 100_000

    func walk(
        root: URL,
        excludedDirectoryNames: Set<String>,
        maximumPaths: Int = DirectoryWalker.defaultMaximumPaths,
        maximumDirectories: Int = DirectoryWalker.defaultMaximumDirectories
    ) throws -> [IndexedPath] {
        var results: [IndexedPath] = []
        var state = WalkState()
        let context = WalkContext(
            root: root.standardizedFileURL,
            excludedDirectoryNames: excludedDirectoryNames,
            maximumPaths: maximumPaths,
            maximumDirectories: maximumDirectories
        )
        try walk(
            directory: context.root,
            context: context,
            ancestorHidden: false,
            state: &state,
            into: &results
        )
        return results
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .isSymbolicLinkKey,
    ]

    private func walk(
        directory: URL,
        context: WalkContext,
        ancestorHidden: Bool,
        state: inout WalkState,
        into results: inout [IndexedPath]
    ) throws {
        guard !Task.isCancelled, state.directoriesEntered < context.maximumDirectories else { return }
        guard let identity = PhysicalFileIdentity(url: directory).fileObjectID else {
            throw WalkFailure.directoryIdentityUnavailable
        }
        // Symlink loop guard over the ANCESTOR chain only. A walk-global "seen"
        // set would let whichever of `link -> v2` and `v2` is enumerated first
        // hide the other, so `v2/page.md` could vanish from the index depending
        // on directory enumeration order.
        guard state.visited.insert(identity).inserted else { return }
        defer { state.visited.remove(identity) }
        state.directoriesEntered += 1
        // An unreadable child must not silently turn a partial scan into a
        // complete, actionable index. Let the owner publish `.failed`.
        let children = try listChildren(directory.resolvingSymlinksInPath())

        for child in children {
            guard !Task.isCancelled, results.count < context.maximumPaths,
                  state.directoriesEntered < context.maximumDirectories else { return }
            guard let values = try? child.resourceValues(forKeys: Self.resourceKeys) else { continue }
            // Hidden entries are tagged, not dropped: an entry is hidden if
            // its own basename starts with `.` OR any ancestor directory
            // (below `root`) already is, so a non-dotfile inside a hidden
            // directory (e.g. `.github/workflows/ci.yml`) still counts as
            // hidden -- matching how every comparable tool treats hidden
            // directories, not just hidden filenames. Tagging (rather than
            // the previous unconditional skip) is what lets folder search
            // opt into hidden entries later without a second directory walk
            // (`IndexedPath.isHidden`'s own doc comment); Quick Open's
            // `query(_:)` filters them back out, so its own behavior is
            // unchanged.
            let isHidden = ancestorHidden || values.isHidden == true
            let name = child.lastPathComponent
            // Resource values describe the link itself on some file
            // systems, so a symlink to a directory can report
            // `isDirectory == false` when queried unresolved — mirrors
            // `FileSystemDirectoryReader.contents(of:)`'s existing
            // resolve-and-recheck for symlinks (`DirectoryReading.swift`),
            // without which a symlinked directory would be misclassified as
            // a file and its subtree silently dropped from the index.
            let isSymbolicLink = values.isSymbolicLink == true
            let targetValues = isSymbolicLink
                ? try? child.resolvingSymlinksInPath().resourceValues(forKeys: Self.resourceKeys)
                : nil
            let isDirectory = values.isDirectory == true || targetValues?.isDirectory == true
            let isPackage = values.isPackage == true || targetValues?.isPackage == true
            // Rebind to the lexical parent so a symlinked root's children
            // keep the user-facing path, matching `FileTree`'s own
            // lexical-parent convention (`DirectoryReading.swift`).
            let lexicalChild = directory.appendingPathComponent(name, isDirectory: isDirectory)
            if isDirectory, isPackage {
                continue // `.app`, `.textbundle`, …: opaque directories, not files to open or search
            }
            if isDirectory {
                guard !context.excludedDirectoryNames.contains(name) else { continue }
                try walk(
                    directory: lexicalChild,
                    context: context,
                    ancestorHidden: isHidden,
                    state: &state,
                    into: &results
                )
            } else {
                results.append(IndexedPath(
                    relativePath: relativePath(of: lexicalChild, relativeTo: context.root),
                    basename: name,
                    isHidden: isHidden
                ))
            }
        }
    }

    private func relativePath(of url: URL, relativeTo root: URL) -> String {
        let rootComponents = root.pathComponents
        let components = url.pathComponents
        guard components.count > rootComponents.count else { return url.lastPathComponent }
        return components[rootComponents.count...].joined(separator: "/")
    }
}
