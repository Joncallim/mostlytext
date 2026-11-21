import Foundation

/// One indexed path under a workspace root — the fixed record
/// `WorkspaceFileIndex` snapshots and `FuzzyPathScore` ranks against.
public struct IndexedPath: Sendable, Equatable, Hashable {
    /// Root-relative path, `/`-separated, no leading slash.
    public let relativePath: String
    public let basename: String
    /// True when this entry's own basename starts with `.`, OR any
    /// directory component between the root and this entry does. Computed
    /// once at walk time (issue #112's own "hidden-file toggle" needs to
    /// know this per entry) so Quick Open (`query(_:)`, always excludes
    /// hidden entries — unchanged behavior) and folder search
    /// (`allPaths(includeHidden:)`, opt-in) can both read the same single
    /// walk's result rather than needing two separate directory walks.
    public let isHidden: Bool
    /// Folded and decomposed once at construction (index-build time, which
    /// happens far less often than every Quick Open keystroke), not
    /// recomputed on every `query(_:)` call — see
    /// `FuzzyPathScore.score(foldedQuery:foldedPath:foldedBasename:)`'s own
    /// doc comment for the 100k-path performance finding this avoids.
    let foldedRelativePath: FuzzyPathScore.FoldedText
    let foldedBasename: FuzzyPathScore.FoldedText

    public init(relativePath: String, basename: String, isHidden: Bool = false) {
        self.relativePath = relativePath
        self.basename = basename
        self.isHidden = isHidden
        foldedRelativePath = FuzzyPathScore.FoldedText(relativePath)
        foldedBasename = FuzzyPathScore.FoldedText(basename)
    }
}
