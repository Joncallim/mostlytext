import Darwin
import Foundation

public extension ThemeCatalogStore {
    func observeChanges() throws -> AsyncStream<ThemeCatalogChange> {
        guard eventObserver == nil else { throw ThemeStorageError.alreadyObserving }
        try directory.checkRoot()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(directory.descriptor, F_GETPATH, &path) == 0 else { throw directory.failure() }
        let observer = try ThemeCatalogEvents(path: String(cString: path))
        eventObserver = observer
        // If the name changed during setup, keep the slot occupied until the
        // caller explicitly stops/drains this stream; never spawn replacements.
        try directory.checkRoot()
        return observer.events
    }

    func stopObserving() async {
        guard let observer = eventObserver else { return }
        await observer.cancelAndWait()
        if eventObserver === observer {
            eventObserver = nil
        }
    }
}
