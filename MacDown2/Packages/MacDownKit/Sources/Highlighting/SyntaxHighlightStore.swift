import AppKit
import EditorCore
import Observation
import Themes

/// Caches one `SyntaxHighlighting` per tab identity. Parallels `EditorTextSystemStore`.
///
/// Observable only through ``states``, so a view can show that a document's
/// highlighting is reduced (register row H5) without observing the cache.
@MainActor
@Observable
public final class SyntaxHighlightStore {
    @ObservationIgnored private var highlighters: [String: SyntaxHighlighting] = [:]
    @ObservationIgnored private let registry: GrammarRegistry
    /// Each live highlighter's state, by identity.
    public private(set) var states: [String: HighlightingState] = [:]

    public init(registry: GrammarRegistry = GrammarRegistry()) {
        self.registry = registry
    }

    /// Returns the existing highlighter or builds one for this text system.
    ///
    /// If a cached highlighter exists but was built for a different language,
    /// `setLanguage` is called on it so the grammar stays in sync with the
    /// document format (e.g., after Save As).
    public func highlighter(
        for identity: String,
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme
    ) -> SyntaxHighlighting {
        if let existing = highlighters[identity] {
            if existing.languageID != languageID {
                existing.setLanguage(languageID)
            }
            (existing as? NeonSyntaxHighlighter)?.resumeViewportIfMounted()
            return existing
        }
        let newHighlighter = NeonSyntaxHighlighter(
            textSystem: textSystem,
            languageID: languageID,
            theme: theme,
            registry: registry,
            enableViewport: true
        )
        highlighters[identity] = newHighlighter
        states[identity] = newHighlighter.state
        newHighlighter.onStateChange = { [weak self] state in
            self?.states[identity] = state
        }
        return newHighlighter
    }

    /// Removes the cached highlighter for `identity` and tears it down.
    public func evict(_ identity: String) {
        highlighters[identity]?.onStateChange = nil
        highlighters[identity]?.tearDown()
        highlighters.removeValue(forKey: identity)
        states.removeValue(forKey: identity)
    }

    /// Removes every cached highlighter. Call when the owning window closes.
    public func evictAll() {
        for highlighter in highlighters.values {
            highlighter.onStateChange = nil
            highlighter.tearDown()
        }
        highlighters.removeAll()
        states.removeAll()
    }

    /// Re-theme every live highlighter.
    public func applyThemeToAll(_ theme: Theme) {
        for highlighter in highlighters.values {
            highlighter.applyTheme(theme)
        }
    }

    /// Restyle every live highlighter for a new base font.
    public func applyFontToAll(_ font: NSFont) {
        for highlighter in highlighters.values {
            highlighter.applyFont(font)
        }
    }

    /// The state of the highlighter for `identity`, if one is live.
    public func state(for identity: String) -> HighlightingState? {
        states[identity]
    }

    /// The identities currently held in the cache.
    public var liveIdentities: Set<String> {
        Set(highlighters.keys)
    }
}
