import ExportService
import Foundation
import MarkdownEngine
import Observation

/// Owns source authority separately from copied views and queued link actions.
/// The physical worker survives cancellation until its bounded work returns.
@MainActor
@Observable
final class HeadingPreviewSession {
    enum Phase { case idle, analyzing, ready, failed }

    struct Display: Sendable {
        let bindingID: UUID
        let preparation: HeadingAnchorPreparation
    }

    private(set) var binding: PreviewSourceBinding?
    private(set) var preparation: HeadingAnchorPreparation?
    private(set) var phase = Phase.idle

    var publicationID: UUID? {
        phase == .ready || phase == .failed ? binding?.id : nil
    }

    @ObservationIgnored private let worker: HeadingPreparationWorker?
    @ObservationIgnored private let compute: @Sendable (HeadingPreparationRequest) async -> HeadingPreparationWorker
        .Outcome

    init() {
        let worker = HeadingPreparationWorker()
        self.worker = worker
        compute = { await worker.submit($0) }
    }

    init(compute: @escaping @Sendable (HeadingPreparationRequest) async -> HeadingPreparationWorker.Outcome) {
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
        preparation = nil
        phase = .idle
    }

    func refresh(
        binding candidate: PreviewSourceBinding, document: MarkdownDocument,
        live: @MainActor () -> PreviewLiveSource?
    ) async {
        guard !Task.isCancelled, candidate.isCurrent(live()),
              document.revision == candidate.stamp.parsedRevision,
              document.sourceSHA256 == candidate.stamp.sourceSHA256 else { return }
        invalidate()
        binding = candidate
        phase = .analyzing
        let stamp = candidate.stamp
        let outcome = await compute(.init(
            document: document, sourceText: candidate.source, documentID: stamp.documentID,
            recoveryEpoch: stamp.recoveryEpoch, sourceGeneration: stamp.mutationGeneration
        ))
        guard binding?.id == candidate.id else { return }
        guard !Task.isCancelled, candidate.isCurrent(live()) else {
            invalidate()
            return
        }
        switch outcome {
        case let .completed(value):
            let identity = value.index.identity
            guard identity.documentID == stamp.documentID, identity.recoveryEpoch == stamp.recoveryEpoch,
                  identity.sourceGeneration == stamp.mutationGeneration, identity.sourceSHA256 == stamp.sourceSHA256,
                  identity.parseRevision == stamp.parsedRevision, identity.parseOptions == document.options else {
                phase = .failed
                return
            }
            preparation = value
            phase = .ready
        case .failed: phase = .failed
        case .cancelled, .superseded: invalidate()
        }
    }

    func currentPreparation(live: PreviewLiveSource?) -> HeadingAnchorPreparation? {
        guard phase == .ready, binding?.isCurrent(live) == true else { return nil }
        return preparation
    }

    func navigationHeading(
        bindingID: UUID, heading: HeadingAnchorIndex.Heading, identity: HeadingAnchorIdentity,
        live: PreviewLiveSource?
    ) -> HeadingAnchorIndex.Heading? {
        guard let binding, phase == .ready, let preparation, preparation.index.identity == identity,
              binding.allowsNavigation(frameID: bindingID, currentFrameID: binding.id, live: live) else { return nil }
        return preparation.index.headings.first {
            $0 == heading && $0.fragment.utf8.elementsEqual(heading.fragment.utf8)
        }
    }
}

struct HeadingPreviewAction: Sendable {
    let bindingID: UUID
    let heading: HeadingAnchorIndex.Heading
    let identity: HeadingAnchorIdentity
}
