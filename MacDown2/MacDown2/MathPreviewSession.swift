import Foundation
import MarkdownEngine
import Math
import MathRendering
import Observation

struct MathPreviewSourceLocation: Sendable, Equatable {
    let range: Range<Int>
    let diagnosticOffset: Int?
}

/// The live session owns analysis authority, independently of SwiftUI View
/// copies and native layout caches. The renderer installs only a current frame.
@MainActor
@Observable
final class MathPreviewSession {
    enum Phase { case idle, analyzing, preparing, ready }

    struct PendingNavigation {
        let frameID: UUID
        let sourceID: UUID
        let diagnostic: Bool
        let token: UInt
    }

    var pendingNavigation: PendingNavigation?

    private(set) var binding: MathPreviewSourceBinding?
    private(set) var evaluation: MathEvaluation?
    private(set) var presentationPlan: MathPresentationPlan?
    private(set) var evaluationID: UUID?
    private(set) var currentFrameID: UUID?
    private(set) var analysisFailed = false
    private(set) var phase = Phase.idle

    var isBusy: Bool {
        phase == .analyzing || phase == .preparing
    }

    @ObservationIgnored private let worker: MathEvaluationWorker?
    @ObservationIgnored private let compute: @Sendable (MathEvaluationRequest) async -> MathEvaluationWorker.Outcome
    @ObservationIgnored private var allowedRanges: [UUID: Range<Int>] = [:]
    @ObservationIgnored private var locations: [UUID: MathPreviewSourceLocation] = [:]

    init() {
        let worker = MathEvaluationWorker()
        self.worker = worker
        compute = { await worker.submit($0) }
    }

    /// Internal injection tests late completions; production always uses the
    /// real worker with its qualified single physical slot and newest pending job.
    init(compute: @escaping @Sendable (MathEvaluationRequest) async -> MathEvaluationWorker.Outcome) {
        worker = nil
        self.compute = compute
    }

    deinit {
        if let worker {
            Task { await worker.shutdown() }
        }
    }

    func invalidate() {
        binding = nil
        evaluation = nil
        presentationPlan = nil
        evaluationID = nil
        currentFrameID = nil
        analysisFailed = false
        allowedRanges = [:]
        locations = [:]
        phase = .idle
        pendingNavigation = nil
    }

    func refresh(
        binding candidate: MathPreviewSourceBinding, document: MarkdownDocument,
        live: @MainActor () -> MathPreviewLiveSource?
    ) async {
        invalidate()
        guard !Task.isCancelled, candidate.isCurrent(live()),
              candidate.stamp.parsedRevision == document.revision,
              candidate.stamp.sourceSHA256 == document.sourceSHA256 else { return }
        binding = candidate
        phase = .analyzing
        let policy = MathProcessingPolicy.standard
        let request = MathEvaluationRequest(
            source: candidate.source, document: document, sourceIdentity: .init(rawValue: candidate.id),
            generation: UInt64(candidate.stamp.mutationGeneration), maximumSpanCount: policy.maximumSpanCount,
            bodyLimits: policy.bodyLimits
        )
        let outcome = await compute(request)
        guard binding?.id == candidate.id else { return }
        guard !Task.isCancelled, candidate.isCurrent(live()) else {
            invalidate()
            return
        }
        switch outcome {
        case let .completed(value):
            accept(value, candidate: candidate, document: document)
        case .failed:
            analysisFailed = true
            evaluationID = UUID()
            phase = .preparing
        case .cancelled, .superseded:
            invalidate()
        }
    }

    private func accept(_ value: MathEvaluation, candidate: MathPreviewSourceBinding, document: MarkdownDocument) {
        do {
            guard value.analysis.sourceIdentity.rawValue == candidate.id,
                  value.analysis.sourceSHA256 == candidate.stamp.sourceSHA256,
                  value.analysis.revision == candidate.stamp.parsedRevision
            else { throw MathAnalysisError.sourceMismatch }
            let plan = try MathPresentationPlan(evaluation: value, document: document)
            var ranges: [UUID: Range<Int>] = [:]
            for entry in value.entries {
                guard ranges.updateValue(entry.equation.syntax.fullRange, forKey: entry.id) == nil else {
                    throw MathAnalysisError.sourceMismatch
                }
            }
            if let id = plan.literalRemainderID, let range = plan.literalRemainderRange {
                guard ranges.updateValue(range, forKey: id) == nil else { throw MathAnalysisError.sourceMismatch }
            }
            allowedRanges = ranges
            evaluation = value
            presentationPlan = plan
        } catch {
            analysisFailed = true
        }
        evaluationID = UUID()
        phase = .preparing
    }

    func installPresentation(
        id: UUID, bindingID: UUID, locations: [UUID: MathPreviewSourceLocation], live: MathPreviewLiveSource?
    ) -> Bool {
        guard phase == .preparing || phase == .ready,
              let binding, binding.id == bindingID, binding.isCurrent(live), !Task.isCancelled else { return false }
        let original = binding.source as NSString
        for (sourceID, location) in locations {
            guard allowedRanges[sourceID] == location.range else { return false }
            if let offset = location.diagnosticOffset {
                guard location.range.lowerBound <= offset, offset <= location.range.upperBound,
                      Self.boundary(offset, in: original) else { return false }
            }
        }
        self.locations = locations
        currentFrameID = id
        phase = .ready
        return true
    }

    func navigationLocation(frameID: UUID, sourceID: UUID, live: MathPreviewLiveSource?) -> MathPreviewSourceLocation? {
        guard let binding, let currentFrameID,
              binding.allowsNavigation(frameID: frameID, currentFrameID: currentFrameID, live: live) else { return nil }
        return locations[sourceID]
    }

    private static func boundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset >= 0, offset <= source.length else { return false }
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1), current = source.character(at: offset)
        return !(previous == 13 && current == 10) &&
            !((0xD800 ... 0xDBFF).contains(previous) && (0xDC00 ... 0xDFFF).contains(current))
    }
}
