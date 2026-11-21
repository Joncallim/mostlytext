import Foundation

/// identity (tab UUID string) → session. Mirrors EditorTextSystemStore.
@MainActor
public final class MarkdownParseStore {
    private let engine: any ParseExecuting
    private let debounce: Duration
    private var sessions: [String: MarkdownParseSession] = [:]

    public init(engine: any ParseExecuting = ParseEngine(), debounce: Duration = .milliseconds(150)) {
        self.engine = engine
        self.debounce = debounce
    }

    public func session(for identity: String) -> MarkdownParseSession {
        if let session = sessions[identity] {
            return session
        }
        let session = MarkdownParseSession(engine: engine, debounce: debounce)
        sessions[identity] = session
        return session
    }

    public func existingSession(for identity: String) -> MarkdownParseSession? {
        sessions[identity]
    }

    public func evict(_ identity: String) {
        sessions.removeValue(forKey: identity)?.cancelPending()
    }

    public func evictAll() {
        for session in sessions.values {
            session.cancelPending()
        }
        sessions.removeAll()
    }
}
