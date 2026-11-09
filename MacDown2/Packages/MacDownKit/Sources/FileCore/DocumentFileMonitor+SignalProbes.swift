import Foundation

extension DocumentFileMonitor {
    func startOrQueueSignalProbe(generation: UInt, sequence: UInt) {
        guard isCurrent(generation: generation, sequence: sequence) else { return }
        if activeSignalProbe != nil {
            readySignalProbeSequence = sequence
            return
        }
        activeSignalProbe = (generation, sequence)
        Task { [weak self] in
            await self?.runSignalProbes(generation: generation, sequence: sequence)
        }
    }

    func runSignalProbes(generation: UInt, sequence: UInt) async {
        var currentSequence = sequence
        while true {
            await probeAfterSignal(generation: generation, sequence: currentSequence)
            // Bind/cancel can replace this admission lane while an older
            // filesystem read is suspended. Its completion owns no new lane.
            guard activeSignalProbe?.generation == generation,
                  activeSignalProbe?.sequence == currentSequence
            else { return }
            guard let ready = readySignalProbeSequence,
                  isCurrent(generation: generation, sequence: ready)
            else {
                activeSignalProbe = nil
                readySignalProbeSequence = nil
                return
            }
            readySignalProbeSequence = nil
            activeSignalProbe = (generation, ready)
            currentSequence = ready
        }
    }
}
