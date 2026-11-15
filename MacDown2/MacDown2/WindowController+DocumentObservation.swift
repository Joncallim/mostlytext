import Observation

extension WindowController {
    func startObservingActiveDocument() {
        // Observation fires once. Rearm after the mutation is published on the
        // main actor, without retaining the window across an idle suspension.
        // The former continuation-based observer could not be cancelled when
        // its source never changed; the later timer woke every open window.
        guard !isClosed else { return }
        withObservationTracking {
            _ = model.tabStore.activeDocument
            _ = model.tabStore.activeTab?.syntaxFormat
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                updateTitleAndEditedState()
                startObservingActiveDocument()
            }
        }
    }
}
