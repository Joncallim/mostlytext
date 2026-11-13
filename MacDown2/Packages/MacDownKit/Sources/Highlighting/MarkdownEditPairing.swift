import Foundation

/// Pairs an editor's pre-mutation proposal with the storage delegate's actual
/// post-mutation edit. The selector may copy a bounded old-source window, but
/// this type never retains the mutable `NSString` supplied by TextKit.
///
/// A veto, nested edit, undo or programmatic replacement has no trustworthy
/// pairing. The caller must then discard its incremental candidate and take
/// its deferred full-parse or plain fallback path. A match establishes edit
/// geometry only; later parsing and painting still need an editor-revision
/// guard so an old completion cannot style a newer document.
@MainActor
final class MarkdownEditPairing<Candidate> {
    private static var maximumReplacementUTF16Units: Int {
        65536
    }

    struct Match {
        let candidate: Candidate
        let oldRange: NSRange
        let newRange: NSRange
        let delta: Int
    }

    private struct Proposal {
        let candidate: Candidate
        let oldRange: NSRange
        let replacement: String
        let oldLength: Int
    }

    private var proposal: Proposal?
    private var sawPreEdit = false
    private var ambiguous = false

    func prepare(range: NSRange, replacement: String, oldSource: NSString,
                 select: (NSString, NSRange, String) -> Candidate?) {
        if sawPreEdit || ambiguous {
            proposal = nil
            ambiguous = true
            return
        }
        // An unsupported or vetoed proposal still occupies this edit cycle.
        // A second callback before storage reports the outcome cannot be
        // trusted as the only mutation, even if the first selector returned nil.
        sawPreEdit = true
        guard range.location != NSNotFound, range.location >= 0,
              range.length >= 0, range.location <= oldSource.length,
              range.length <= oldSource.length - range.location,
              (replacement as NSString).length <= Self.maximumReplacementUTF16Units,
              let candidate = select(oldSource, range, replacement)
        else { return }
        proposal = Proposal(candidate: candidate, oldRange: range,
                            replacement: replacement, oldLength: oldSource.length)
    }

    func complete(editedRange: NSRange, delta: Int, postSource: NSString) -> Match? {
        defer { discard() }
        guard !ambiguous, let proposal else { return nil }
        let replacementLength = (proposal.replacement as NSString).length
        let (expectedLength, overflow) = proposal.oldLength.addingReportingOverflow(delta)
        guard editedRange.location == proposal.oldRange.location,
              editedRange.length == replacementLength,
              delta == replacementLength - proposal.oldRange.length,
              !overflow, postSource.length == expectedLength,
              editedRange.location <= postSource.length,
              editedRange.length <= postSource.length - editedRange.location,
              postSource.substring(with: editedRange) == proposal.replacement
        else { return nil }
        return Match(candidate: proposal.candidate, oldRange: proposal.oldRange,
                     newRange: editedRange, delta: delta)
    }

    func discard() {
        proposal = nil
        sawPreEdit = false
        ambiguous = false
    }
}
