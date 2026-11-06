import Foundation
import os
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Maps a `FileFormat.highlightLanguageID` to a tree-sitter `LanguageConfiguration`.
///
/// Lazily builds + caches; every failure is caught and cached as `nil` so a bad
/// grammar downgrades that one language to plain text rather than crashing or
/// failing the build.
///
/// Resolution is thread-safe: `LanguageLayer.LanguageProvider` is invoked on
/// Neon's background processor while initial highlighting resolves grammars on
/// the main thread, so the shared cache lives in the lock-guarded
/// `ConfigurationCache` rather than on this `@MainActor` shell.
@MainActor
public final class GrammarRegistry {
    /// The cache is a `let` of `Sendable` type, so it can be accessed from a
    /// `nonisolated` context. This lets `languageProvider` be obtained on any
    /// isolation domain while still returning a closure that is safe to invoke
    /// from Neon's background queue.
    private nonisolated let configurations = ConfigurationCache()

    private nonisolated let beforeInjectedLanguageResolution: (@Sendable (String) -> Void)?

    public init() {
        beforeInjectedLanguageResolution = nil
    }

    /// Allows a controlled integration fixture to hold a real background lookup without holding the cache lock.
    init(beforeInjectedLanguageResolution: @escaping @Sendable (String) -> Void) {
        self.beforeInjectedLanguageResolution = beforeInjectedLanguageResolution
    }

    /// `nil` ⇒ no grammar for this id ⇒ caller must degrade to plain text. Never throws.
    public nonisolated func configuration(for highlightLanguageID: String?) -> LanguageConfiguration? {
        configurations.configuration(for: highlightLanguageID)
    }

    /// The language provider Neon/SwiftTreeSitterLayer call to resolve injected
    /// languages (e.g. `markdown_inline`, or a fenced code block's info-string
    /// language). Returns `nil` for unknown injected languages so that region
    /// stays plain.
    ///
    /// The returned closure is designed to be invoked off the main thread; it
    /// captures the thread-safe cache directly instead of hopping to the main
    /// actor (a synchronous hop would risk deadlock against the background
    /// processor). Marking the property `nonisolated` makes this isolation split
    /// explicit.
    public nonisolated var languageProvider: LanguageLayer.LanguageProvider {
        let configurations = configurations
        let beforeResolution = beforeInjectedLanguageResolution
        return { name in
            beforeResolution?(name)
            return configurations.configuration(for: name)
        }
    }

    /// Ids the registry can currently satisfy.
    public nonisolated var supportedLanguageIDs: Set<String> {
        configurations.supportedLanguageIDs
    }
}

/// Lock-guarded build cache backing `GrammarRegistry`.
///
/// Grammar resolution must be safe to call from any thread (see
/// `GrammarRegistry.languageProvider`), so all access to the cache dictionary
/// is serialized by `NSLock`. To avoid blocking cache hits behind a grammar
/// build, the lock is released around `buildConfiguration(for:)`. A race
/// between two misses for the same id may build the grammar more than once,
/// but the result is identical and the final write is still serialized.
///
/// Callers that hold external locks must not call `configuration(for:)` while
/// holding them; the cache's own lock is sufficient.
///
/// Internal (not file-private) so the grammar build recipes can live in
/// `GrammarRegistry+Factories.swift` as an extension without widening the
/// module's public surface.
final class ConfigurationCache: @unchecked Sendable {
    private var storage: [String: LanguageConfiguration?] = [:]
    private let lock = NSLock()
    private let logger = Logger()

    /// `nil` ⇒ no grammar for this id ⇒ caller must degrade to plain text. Never throws.
    func configuration(for highlightLanguageID: String?) -> LanguageConfiguration? {
        guard let id = highlightLanguageID else { return nil }

        // Check under the lock first. Cache hits return immediately; only a
        // miss pays the cost of building the grammar.
        lock.lock()
        if let cached = storage[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Build outside the lock so other threads (and other language ids) can
        // still read the cache while file I/O / query compilation runs.
        let config: LanguageConfiguration? = {
            do {
                return try buildConfiguration(for: id)
            } catch {
                logger.log("Grammar '\(id)' failed to load: \(error)")
                return nil
            }
        }()

        // Re-acquire the lock and recheck before writing: another thread may
        // have built and stored the same grammar while we were working.
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[id] {
            return cached
        }
        storage[id] = config
        return config
    }

    /// Ids the registry can currently satisfy.
    var supportedLanguageIDs: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Self.knownLanguageIDs.union(storage.compactMap { $0.value != nil ? $0.key : nil })
    }

    private static let knownLanguageIDs: Set<String> = [
        "markdown",
        "markdown_inline",
        "json",
        "html",
        // EPIC-11 Gate 5: the remaining advertised highlight languages. Each
        // id must resolve to a built, query-backed configuration or the
        // registry consistency test fails (no advertised language may silently
        // degrade).
        "yaml",
        "toml",
        "javascript",
        "typescript",
        "python",
        "ruby",
        "css",
        "swift",
        "cpp",
        "bash",
        "sql",
        "xml",
    ]
}

// MARK: - Minimal logging

private struct Logger {
    private let log = OSLog(subsystem: "com.macdown2.MacDownKit", category: "GrammarRegistry")

    func log(_ message: @autoclosure () -> String) {
        let msg = message()
        #if DEBUG
            print(msg)
        #endif
        os_log(.info, log: log, "%{public}@", msg)
    }
}
