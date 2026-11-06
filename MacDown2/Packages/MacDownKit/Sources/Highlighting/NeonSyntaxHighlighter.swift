import AppKit
import EditorCore
import Neon
import RangeState
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Themes

/// Concrete highlighter: wraps Neon's `TextViewHighlighter` over an E04 `EditorTextSystem`.
///
/// Size fallback (register row H5): for a language with a
/// ``HighlightingSizePolicy``, a document longer than the cut-off gets no
/// tree-sitter parser — not on open, restore, reload or a language change, and
/// not on the edit that crosses the cut-off, which a ``HighlightingStorageGate``
/// withholds from Neon before Neon's synchronous reparse. ``state`` reports the
/// requested language and the effective mode separately. See
/// `NeonSyntaxHighlighter+SizeFallback.swift`.
@MainActor
public final class NeonSyntaxHighlighter: SyntaxHighlighting {
    let textSystem: EditorTextSystem
    let registry: GrammarRegistry
    private var currentTheme: Theme
    /// Neon's highlighter while ``state`` is `.full`; `nil` otherwise.
    var highlighter: TextViewHighlighter?
    public private(set) var languageID: String?
    private var baseFont: NSFont
    /// Tokens Neon has styled so far. Lets tests detect when highlighting has
    /// gone quiet without reaching into Neon's private state.
    private(set) var styledTokenCount = 0
    /// Bumped whenever a Neon highlighter is built or discarded. A discarded
    /// highlighter's in-flight work cannot be cancelled (Neon exposes no
    /// cancellation), so its attribute provider checks this and styles nothing.
    var generation: UInt64 {
        get { layerState.generation }
        set { layerState.generation = newValue }
    }

    /// Shared with Neon's closures, which run on its background queue.
    let layerState = LayerRequestState()
    /// Styling requests that arrived from a discarded highlighter's late work.
    private(set) var staleStyleRequestCount = 0
    /// Parse-adjacent requests Neon made through the language provider and the
    /// location transformer, split by whether the highlighter that made them
    /// is still current. Stale ones are a discarded highlighter's surviving
    /// work entering the tree-sitter layer (register row H5).
    var liveLayerRequestCount: Int {
        layerState.liveCount
    }

    var staleLayerRequestCount: Int {
        layerState.staleCount
    }

    /// Times the highlighter-owned presentation was cleared, and when (uptime
    /// ns) it last was: lets benchmarks time "reduced mode has settled".
    var presentationClearCount = 0
    var lastPresentationClearUptime: UInt64 = 0
    let gate = HighlightingStorageGate()
    let policyProvider: (String?) -> HighlightingSizePolicy?
    var restoreTask: Task<Void, Never>?
    /// Internal clock seam for deterministic idle-restore tests. Production uses Task.sleep.
    var restoreSleep: (@MainActor (Duration) async throws -> Void)?
    /// After a restore from reduced mode, Neon's first pass of rendering attributes can land without TextKit
    /// repainting (seen on the native app: attributes present, text still plain until the next edit). Until this
    /// uptime (ns) each pass of styling is followed by one coalesced repaint request.
    var repaintDeadline: UInt64 = 0
    var repaintScheduled = false
    var repaintCount = 0

    public private(set) var state: HighlightingState {
        didSet {
            if state != oldValue {
                onStateChange?(state)
            }
        }
    }

    public var onStateChange: ((HighlightingState) -> Void)?

    /// - textSystem: the E04 system whose `.textView` we attach to.
    /// - languageID: `FileFormat.highlightLanguageID` (nil / unknown ⇒ plain text + chrome only).
    /// - theme: initial theme; chrome is applied to the text view immediately.
    /// - registry: shared grammar registry.
    /// - sizePolicy: the size fallback per language (tests pass `{ _ in nil }`
    ///   to measure Neon unbounded).
    public init(
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme,
        registry: GrammarRegistry,
        sizePolicy: @escaping (String?) -> HighlightingSizePolicy? = HighlightingSizePolicy.default(for:)
    ) {
        self.textSystem = textSystem
        self.languageID = languageID
        self.registry = registry
        policyProvider = sizePolicy
        currentTheme = theme
        baseFont = textSystem.textView.font
            ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        state = HighlightingState(requestedLanguageID: languageID, mode: .plain)

        applyChrome(theme: theme)
        installGate()
        configure(languageID: languageID)
    }

    // MARK: - SyntaxHighlighting

    public func applyTheme(_ theme: Theme) {
        currentTheme = theme
        applyChrome(theme: theme)
        highlighter?.invalidate(.all)
    }

    public func applyFont(_ font: NSFont) {
        guard font != baseFont else { return }
        baseFont = font
        highlighter?.invalidate(.all)
    }

    public func setLanguage(_ highlightLanguageID: String?) {
        guard languageID != highlightLanguageID else { return }
        languageID = highlightLanguageID
        configure(languageID: highlightLanguageID)
    }

    public func invalidateAll() {
        highlighter?.invalidate(.all)
    }

    public func tearDown() {
        restoreTask?.cancel()
        restoreTask = nil
        discardHighlighter()
        clearHighlighterPresentation()
        if let storage = textSystem.textView.textStorage {
            gate.uninstall(from: storage)
        }
    }

    /// Sets the effective mode for the current requested language.
    func setMode(_ mode: HighlightingState.Mode) {
        state = HighlightingState(requestedLanguageID: languageID, mode: mode)
    }

    // MARK: - Internal

    private func applyChrome(theme: Theme) {
        let textView = textSystem.textView
        let palette = ResolvedPresentationPalette(theme: theme)
        textView.backgroundColor = palette.background.nsColor
        textView.textColor = palette.foreground.nsColor
        textView.insertionPointColor = palette.caret.nsColor
        textView.selectedTextAttributes = [.backgroundColor: palette.selectionBackground.nsColor]
        if let editor = textView as? EditorTextView {
            editor.invisiblesColor = palette.invisibles.nsColor
            editor.currentLineColor = palette.currentLine.nsColor
            editor.gutterForegroundColor = palette.gutterForeground.nsColor
            editor.gutterBackgroundColor = palette.gutterBackground.nsColor
        }
    }

    /// Builds Neon's highlighter for `config` and puts the gate back in front
    /// of the storage delegate Neon installs. Returns false if Neon failed.
    func buildHighlighter(config: LanguageConfiguration) -> Bool {
        generation &+= 1
        let builtGeneration = generation
        do {
            let attributeProvider: TokenAttributeProvider = { [weak self] token in
                guard let self else { return [:] }
                guard generation == builtGeneration else {
                    staleStyleRequestCount &+= 1
                    return [:]
                }
                styledTokenCount &+= 1
                requestRepaintIfNeeded()
                let style = currentTheme.style(for: token.name)
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: (style?.color ?? currentTheme.chrome.foreground).nsColor,
                ]
                if let style {
                    attrs[.font] = styledFont(bold: style.bold, italic: style.italic)
                    if style.underline {
                        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    }
                }
                return attrs
            }

            highlighter = try TextViewHighlighter(
                textView: textSystem.textView,
                configuration: TextViewHighlighter.Configuration(
                    languageConfiguration: config,
                    attributeProvider: attributeProvider,
                    languageProvider: { [state = layerState, registryProvider = registry.languageProvider] name in
                        guard state.note(builtGeneration: builtGeneration) else { return nil }
                        return registryProvider(name)
                    },
                    locationTransformer: countedLocationTransformer(builtGeneration: builtGeneration)
                )
            )
            if let storage = textSystem.textView.textStorage {
                gate.adoptDownstream(from: storage)
            }
            return true
        } catch {
            // Graceful degradation: leave highlighter nil, plain text + chrome.
            highlighter = nil
            return false
        }
    }

    private func countedLocationTransformer(builtGeneration: UInt64) -> (Int) -> Point? {
        let transform = Self.locationTransformer(for: textSystem.textView) { [weak textSystem] in
            textSystem?.contentRevision ?? 0
        }
        return { [state = layerState] offset in
            guard state.note(builtGeneration: builtGeneration) else { return nil }
            return transform(offset)
        }
    }

    private func styledFont(bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold {
            traits.insert(.bold)
        }
        if italic {
            traits.insert(.italic)
        }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    /// Maps a UTF-16 offset to a tree-sitter `Point`.
    ///
    /// `row` = number of `\n` before the offset; `column` = byte distance
    /// back to the previous `\n` (or string start). The pinned parser reads
    /// UTF-16, so each code unit contributes two bytes, including surrogates.
    /// Neon converts edit offsets to bytes but forwards these Points unchanged.
    ///
    /// Uses a lazily-built line-offset table with binary search for O(log n)
    /// per-call performance instead of O(n) substring scanning. The table is
    /// rebuilt when the editor revision or document length changes, using a
    /// single character-set scan rather than repeated substring searches.
    static func locationTransformer(
        for textView: NSTextView,
        revision: @escaping () -> UInt64 = { 0 }
    ) -> (Int) -> Point? {
        var lineOffsets: [Int]?
        var cachedRevision: UInt64?
        var cachedLength: Int?

        return { offset in
            let string = textView.string as NSString
            let clamped = max(0, min(offset, string.length))
            let currentRevision = revision()

            // Length-preserving edits can still move every subsequent line.
            // Prefer the editor's generation, with a length fallback for
            // standalone NSTextView callers.
            if lineOffsets == nil || cachedRevision != currentRevision || cachedLength != string.length {
                cachedRevision = currentRevision
                cachedLength = string.length
                lineOffsets = Self.lineOffsets(in: string)
            }

            guard let offsets = lineOffsets, !offsets.isEmpty else {
                return Point(row: 0, column: clamped * 2)
            }

            // Binary search for the row containing `clamped`.
            var low = 0, high = offsets.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if offsets[mid] <= clamped {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            let row = high
            let column = (clamped - offsets[row]) * 2
            return Point(row: row, column: column)
        }
    }

    /// Builds a UTF-16 line-start offset table for `string`.
    ///
    /// Copies the string into a `unichar` buffer and scans it directly, which
    /// benchmarks ~9x faster than `rangeOfCharacter(from:)` on a 630 KB
    /// document (0.21 ms vs 1.99 ms) by avoiding a fresh `NSRange` search per
    /// line. Verified byte-for-byte identical output against the
    /// `rangeOfCharacter(from:)` version it replaced, including the trailing-
    /// newline edge case (a final `\n` still opens an empty last line, at
    /// offset `length`).
    private static func lineOffsets(in string: NSString) -> [Int] {
        var offsets = [0]
        let length = string.length
        guard length > 0 else { return offsets }

        var buffer = [unichar](repeating: 0, count: length)
        string.getCharacters(&buffer, range: NSRange(location: 0, length: length))

        let newline = unichar(10) // "\n"
        for index in 0 ..< length where buffer[index] == newline {
            offsets.append(index + 1)
        }

        return offsets
    }
}

/// The current highlighter generation and the layer requests Neon made, safe
/// to touch from Neon's background queue (`languageProvider` runs there).
///
/// A request from a discarded highlighter is refused: it must not resolve
/// injected layers (the dominant cost) against text it no longer describes.
final class LayerRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var currentGeneration: UInt64 = 0
    private var live = 0
    private var stale = 0

    var generation: UInt64 {
        get { lock.withLock { currentGeneration } }
        set { lock.withLock { currentGeneration = newValue } }
    }

    var liveCount: Int {
        lock.withLock { live }
    }

    var staleCount: Int {
        lock.withLock { stale }
    }

    /// Counts the request; true if the highlighter that made it is current.
    func note(builtGeneration: UInt64) -> Bool {
        lock.withLock {
            if currentGeneration == builtGeneration {
                live &+= 1
                return true
            }
            stale &+= 1
            return false
        }
    }
}
