import Darwin
import Foundation

public extension ThemeCatalogStore {
    func currentDirectoryURL() throws -> URL {
        try directory.checkRoot()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(directory.descriptor, F_GETPATH, &path) == 0 else { throw directory.failure() }
        try directory.checkRoot()
        let bytes = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let string = String(bytes: bytes, encoding: .utf8) else { throw ThemeStorageError.invalidDirectory }
        return URL(fileURLWithPath: string, isDirectory: true)
    }

    func observeChanges() throws -> AsyncStream<ThemeCatalogChange> {
        guard eventObserver == nil else { throw ThemeStorageError.alreadyObserving }
        try directory.checkRoot()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(directory.descriptor, F_GETPATH, &path) == 0 else { throw directory.failure() }
        let bytes = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let string = String(bytes: bytes, encoding: .utf8) else { throw ThemeStorageError.invalidDirectory }
        let observer = try ThemeCatalogEvents(path: string)
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
