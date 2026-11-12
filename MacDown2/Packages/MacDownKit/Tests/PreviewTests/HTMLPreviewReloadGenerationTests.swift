import Foundation
@testable import Preview
import Testing

@Suite("HTMLPreviewReloadGate")
struct HTMLPreviewReloadGateTests {
    @Test func firstRequestIsApproved() {
        var gate = HTMLPreviewReloadGate()
        let approved = gate.shouldLoad(generation: 7)
        #expect(approved)
    }

    @Test func firstZeroGenerationIsApprovedOnceAndCanRetryAfterFailure() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 0)
        #expect(first)
        let duplicate = gate.shouldLoad(generation: 0)
        #expect(!duplicate)
        gate.loadFailed(generation: 0)
        let retry = gate.shouldLoad(generation: 0)
        #expect(retry)
        gate.loadCompleted(generation: 0)
        let completed = gate.shouldLoad(generation: 0)
        #expect(!completed)
    }

    @Test func duplicateRequestIsRejectedBeforeCompletion() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        // Unrelated SwiftUI update re-issuing the pending generation.
        let duplicate = gate.shouldLoad(generation: 7)
        #expect(!duplicate)
    }

    @Test func olderGenerationIsRejectedAfterCompletion() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadCompleted(generation: 7)
        let same = gate.shouldLoad(generation: 7)
        #expect(!same)
        let older = gate.shouldLoad(generation: 3)
        #expect(!older)
    }

    @Test func newerGenerationSupersedesCompletedLoad() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadCompleted(generation: 7)
        let newer = gate.shouldLoad(generation: 9)
        #expect(newer)
    }

    @Test func newerGenerationSupersedesPendingLoad() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        // Save lands before the load completes: the newer revision wins.
        let second = gate.shouldLoad(generation: 9)
        #expect(second)
        let duplicate = gate.shouldLoad(generation: 9)
        #expect(!duplicate)
        let older = gate.shouldLoad(generation: 8)
        #expect(!older)
    }

    @Test func completionForSupersededGenerationIsIgnored() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        let second = gate.shouldLoad(generation: 9)
        #expect(second)
        // The cancelled load 7 must never become the "loaded" revision: the
        // pending gate for 9 stays intact and is not double-issued.
        gate.loadCompleted(generation: 7)
        let duplicateNine = gate.shouldLoad(generation: 9)
        #expect(!duplicateNine, "superseded completion must not clear the pending gate")
        gate.loadCompleted(generation: 9)
        let again = gate.shouldLoad(generation: 9)
        #expect(!again)
        let staleSeven = gate.shouldLoad(generation: 7)
        #expect(!staleSeven)
    }

    @Test func completionRecordsOnlyThePendingGeneration() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadCompleted(generation: 7)
        // A stray completion for an unknown generation is ignored.
        gate.loadCompleted(generation: 99)
        let same = gate.shouldLoad(generation: 7)
        #expect(!same)
        let newer = gate.shouldLoad(generation: 8)
        #expect(newer)
    }

    @Test func cancelPendingDropsOnlyThePendingRequest() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.cancelPendingLoad()
        let reissue = gate.shouldLoad(generation: 7)
        #expect(reissue, "cancelled generation may be re-issued")
    }

    @Test func cancelAfterCompletionDoesNotForgetLoadedGeneration() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadCompleted(generation: 7)
        gate.cancelPendingLoad()
        let same = gate.shouldLoad(generation: 7)
        #expect(!same)
    }

    @Test func repeatedEditSaveCyclesLoadOncePerSavedRevision() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 5)
        #expect(first)
        gate.loadCompleted(generation: 5)
        let second = gate.shouldLoad(generation: 6)
        #expect(second)
        gate.loadCompleted(generation: 6)
        let third = gate.shouldLoad(generation: 7)
        #expect(third)
        let duplicate = gate.shouldLoad(generation: 7)
        #expect(!duplicate)
    }

    @Test func failedGenerationCanBeRetried() {
        // A failed load is not the loaded revision: the same generation may
        // be re-issued so the preview is not wedged stale until the next save.
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadFailed(generation: 7)
        let retry = gate.shouldLoad(generation: 7)
        #expect(retry, "a failed generation must be retriable")
    }

    @Test func failureForSupersededGenerationIsIgnored() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        let second = gate.shouldLoad(generation: 9)
        #expect(second)
        // The interrupted load 7 must not re-arm or clear the pending 9.
        gate.loadFailed(generation: 7)
        let duplicateNine = gate.shouldLoad(generation: 9)
        #expect(!duplicateNine, "superseded failure must not clear the pending gate")
        gate.loadCompleted(generation: 9)
        let again = gate.shouldLoad(generation: 9)
        #expect(!again)
    }

    @Test func failureRecordsNothingForUnknownGeneration() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadFailed(generation: 99)
        // The pending 7 is untouched and still single-issue.
        let duplicate = gate.shouldLoad(generation: 7)
        #expect(!duplicate)
    }

    @Test func retryAfterFailureThenCompletionBlocksFurtherReissues() {
        var gate = HTMLPreviewReloadGate()
        let first = gate.shouldLoad(generation: 7)
        #expect(first)
        gate.loadFailed(generation: 7)
        let retry = gate.shouldLoad(generation: 7)
        #expect(retry)
        gate.loadCompleted(generation: 7)
        let again = gate.shouldLoad(generation: 7)
        #expect(!again)
        let newer = gate.shouldLoad(generation: 8)
        #expect(newer)
    }
}
