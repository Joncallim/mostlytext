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
        let verification: VerificationWindow?
    }

    private struct VerificationWindow {
        let range: NSRange
        let content: String
    }

    private var proposal: Proposal?
    private var sawPreEdit = false
    private var ambiguous = false

    func prepare(range: NSRange, replacement: String, oldSource: NSString,
                 verificationRange: ((Candidate) -> NSRange)? = nil,
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
        var verification: VerificationWindow?
        if let verificationRange {
            let window = verificationRange(candidate)
            guard window.location != NSNotFound, window.location >= 0,
                  window.length > 0, window.length <= Self.maximumReplacementUTF16Units,
                  window.location <= range.location,
                  range.length <= window.length - (range.location - window.location),
                  window.location <= oldSource.length,
                  window.length <= oldSource.length - window.location
            else { return }
            verification = VerificationWindow(range: window, content: oldSource.substring(with: window))
        }
        proposal = Proposal(candidate: candidate, oldRange: range,
                            replacement: replacement, oldLength: oldSource.length,
                            verification: verification)
    }

    func complete(editedRange: NSRange, delta: Int, postSource: NSString) -> Match? {
        defer { discard() }
        guard !ambiguous, let proposal else { return nil }
        let replacementLength = (proposal.replacement as NSString).length
        let (expectedLength, overflow) = proposal.oldLength.addingReportingOverflow(delta)
        let newRange = NSRange(location: proposal.oldRange.location, length: replacementLength)
        guard editedRange.location != NSNotFound, editedRange.location >= 0,
              editedRange.length >= 0,
              delta == replacementLength - proposal.oldRange.length,
              !overflow, postSource.length == expectedLength,
              editedRange.location <= postSource.length,
              editedRange.length <= postSource.length - editedRange.location,
              newRange.location <= postSource.length,
              newRange.length <= postSource.length - newRange.location,
              postSource.substring(with: newRange) == proposal.replacement
        else { return nil }
        if editedRange != newRange {
            guard let verification = proposal.verification,
                  editedRange.location <= newRange.location,
                  NSMaxRange(editedRange) >= NSMaxRange(newRange),
                  verification.range.location <= editedRange.location
            else { return nil }
            let (newWindowLength, windowOverflow) = verification.range.length.addingReportingOverflow(delta)
            guard !windowOverflow, newWindowLength > 0,
                  verification.range.location <= postSource.length,
                  newWindowLength <= postSource.length - verification.range.location,
                  NSMaxRange(editedRange) <= verification.range.location + newWindowLength
            else { return nil }
            let localEdit = NSRange(location: proposal.oldRange.location - verification.range.location,
                                    length: proposal.oldRange.length)
            let expected = (verification.content as NSString).replacingCharacters(
                in: localEdit, with: proposal.replacement
            )
            let newWindow = NSRange(location: verification.range.location, length: newWindowLength)
            guard postSource.substring(with: newWindow) == expected else { return nil }
        }
        return Match(candidate: proposal.candidate, oldRange: proposal.oldRange,
                     newRange: newRange, delta: delta)
    }

    func discard() {
        proposal = nil
        sawPreEdit = false
        ambiguous = false
    }
}
