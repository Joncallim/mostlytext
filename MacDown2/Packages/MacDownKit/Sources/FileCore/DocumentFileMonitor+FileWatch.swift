import Foundation

struct DocumentWatchHandles {
    let parent: any DocumentDirectoryWatcherHandle
    let file: (any DocumentDirectoryWatcherHandle)?

    func cancel() {
        parent.cancel()
        file?.cancel()
    }
}

extension DocumentFileMonitor {
    func isCurrent(generation: UInt, sequence: UInt) -> Bool {
        generation == self.generation && sequence == probeSequence && boundURL != nil
    }

    func watchFileIfAvailable(
        _ url: URL,
        generation: UInt
    ) throws -> (any DocumentDirectoryWatcherHandle)? {
        do {
            return try watcher.watchFile(url) { [weak self] signal in
                Task { await self?.received(signal, generation: generation) }
            }
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    /// Own the parent source until the optional file source has been installed.
    /// A failed file watch must not leave a parent callback live on an error path.
    func makeWatchHandles(for url: URL, generation: UInt) throws -> DocumentWatchHandles {
        let parent = try watcher.watch(url.deletingLastPathComponent()) { [weak self] signal in
            Task { await self?.received(signal, generation: generation) }
        }
        do {
            let file = try watchFileIfAvailable(url, generation: generation)
            return DocumentWatchHandles(parent: parent, file: file)
        } catch {
            parent.cancel()
            throw error
        }
    }

    func installFileWatcherIfNeeded(
        generation: UInt,
        sequence: UInt,
        observation: DocumentFileObservation
    ) async {
        guard fileHandle == nil,
              case let .available(snapshot) = observation,
              isCurrent(generation: generation, sequence: sequence),
              let boundURL,
              snapshot.revision.url.standardizedFileURL == boundURL
        else { return }
        do {
            let replacement = try watchFileIfAvailable(boundURL, generation: generation)
            guard isCurrent(generation: generation, sequence: sequence) else {
                replacement?.cancel()
                return
            }
            fileHandle = replacement
        } catch {
            // Parent monitoring remains authoritative; the next signal retries.
        }
    }
}
