import FileCore
import Foundation

/// One file's worth of an accepted Replace in Folder — data only. The
/// `matches` are UTF-16 ranges into the file exactly as it was when
/// `revision` was read (the `FolderSearchMatch` the user reviewed), so the
/// plan is only ever applicable to content whose hash still equals
/// `revision.sha256`; anything else is `.skippedChangedSinceSearch`, never a
/// splice of stale offsets into different text.
public struct ReplacementPlan: Sendable, Equatable {
    public let relativePath: String
    public let revision: FileRevision
    public let matches: [SearchMatch]
    public let replacementText: String

    public init(relativePath: String, revision: FileRevision, matches: [SearchMatch], replacementText: String) {
        self.relativePath = relativePath
        self.revision = revision
        self.matches = matches
        self.replacementText = replacementText
    }

    public init(_ result: FolderSearchMatch, replacementText: String) {
        self.init(
            relativePath: result.relativePath,
            revision: result.revision,
            matches: result.matches,
            replacementText: replacementText
        )
    }

    /// `text` with every planned range replaced, or `nil` when the plan's
    /// ranges are not a valid, ascending, non-overlapping set of ranges
    /// inside `text` (a corrupt or stale plan must never produce output).
    /// Splices from the highest offset down so earlier ranges are unaffected.
    func applying(to text: String) -> String? {
        let source = text as NSString
        var previousEnd = 0
        for match in matches {
            let range = match.range
            guard range.location != NSNotFound,
                  range.location >= previousEnd,
                  range.length >= 0,
                  range.location <= source.length,
                  range.length <= source.length - range.location
            else { return nil }
            // Check by subtraction first: NSMaxRange can wrap an oversized
            // endpoint and admit a range that makes Foundation throw.
            previousEnd = range.location + range.length
        }
        var result = text as NSString
        let replacement = LineEnding.adaptingLineBreaks(in: replacementText, toMatch: text)
        for match in matches.reversed() {
            result = result.replacingCharacters(in: match.range, with: replacement) as NSString
        }
        return result as String
    }
}

/// What happened to one planned file. Every case other than `.replaced`
/// means the file on disk was left untouched.
public enum ReplacementFileOutcome: Sendable, Equatable {
    case replaced(count: Int)
    /// The file's content differs from what the user reviewed, or changed
    /// between the pre-write read and the conditional publication
    /// (`FileStoreError.fileChangedDuringRead`) — never silently overwritten.
    case skippedChangedSinceSearch
    case skippedUnreadable
    /// The path is, or traverses, a symbolic link. Replace never rewrites
    /// through a link: publication would replace the link itself, or edit a
    /// file outside the folder the user chose.
    case skippedSymbolicLink
    /// The file is open in a window with unsaved edits; a disk rewrite would
    /// fight the in-memory buffer the user has not saved.
    case skippedOpenDocumentWithUnsavedChanges
    /// The plan's ranges are not valid for the file's content, or the
    /// replacement cannot be represented in the file's own encoding without
    /// loss (unreachable with today's UTF-8/UTF-16 decode set; guards the
    /// wider encoding set Slice 8 introduces).
    case skippedCannotRepresent
    case failed(String)
    /// The run was cancelled before this file was attempted.
    case notAttempted
}

/// One line of the before/after preview shown for a file.
public struct ReplacementPreviewLine: Sendable, Equatable {
    /// 1-based.
    public let lineNumber: Int
    public let before: String
    public let after: String

    public init(lineNumber: Int, before: String, after: String) {
        self.lineNumber = lineNumber
        self.before = before
        self.after = after
    }
}

public enum ReplacementFilePreview: Sendable, Equatable {
    /// `lines` is capped at `WorkspaceReplaceEngine.previewLineLimit`;
    /// `totalRegionCount` is the true number of affected line regions (a
    /// multi-line match, or matches on adjacent lines it joins, is one region).
    case lines([ReplacementPreviewLine], totalRegionCount: Int)
    case changedSinceSearch
    case unreadable
    case symbolicLink
}
