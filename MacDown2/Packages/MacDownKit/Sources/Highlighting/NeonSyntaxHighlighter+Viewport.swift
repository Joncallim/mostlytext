import AppKit
import EditorCore
import Neon

/// Bounded mounted Markdown owner. The production store opts in; callers that
/// build this highlighter directly retain their explicit opt-in choice.
extension NeonSyntaxHighlighter {
    /// The hosted Release qualification covers 1,048,804 UTF-8 bytes of
    /// ordinary Markdown. Keep larger sources on the established reduced
    /// fallback until their parse and memory budgets are measured.
    static let viewportMaxUTF16Units = 1_100_000

    /// The window may request highlighting before SwiftUI mounts its editor.
    /// Its later mounted request reuses the cached highlighter, so admission
    /// must be retried there rather than leaving a large document reduced.
    func resumeViewportIfMounted() {
        guard !isTornDown, viewportModeEnabled, state.isReduced,
              viewportSession == nil,
              let policy = policyProvider(languageID),
              documentLength > policy.reduceAboveUTF16Units,
              documentLength <= Self.viewportMaxUTF16Units,
              startViewport()
        else { return }
        setMode(.visibleOnly(.documentTooLarge(limitUTF16Units: policy.reduceAboveUTF16Units)))
    }

    @discardableResult
    func startViewport() -> Bool {
        guard !isTornDown, viewportModeEnabled, languageID == "markdown",
              documentLength <= Self.viewportMaxUTF16Units,
              viewportSession == nil,
              textSystem.preEditObserver == nil,
              textSystem.textView.enclosingScrollView != nil,
              let storage = textSystem.textView.textStorage
        else { return false }

        generation &+= 1
        let builtGeneration = generation
        let session = MarkdownViewportSession(textSystem: textSystem, registry: registry)
        let painter = MarkdownViewportPainter(textSystem: textSystem, session: session) { [weak self] token in
            guard let self, generation == builtGeneration else { return [:] }
            let style = currentTheme.style(for: token.name)
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: (style?.color ?? currentTheme.chrome.foreground).nsColor,
            ]
            if let style {
                attributes[.font] = styledFont(bold: style.bold, italic: style.italic)
                if style.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            return attributes
        }
        viewportSession = session
        viewportPainter = painter
        session.onPublication = { [weak painter] in painter?.scheduleRefresh() }
        textSystem.preEditObserver = { [weak session] range, replacement, source in
            session?.prepare(range: range, replacement: replacement, oldSource: source)
        }
        gate.didProcessCharacterEditWithGeometry = { [weak self, weak storage] range, delta, postEditLength in
            self?.didEditViewport(range: range, delta: delta, postEditLength: postEditLength, storage: storage)
        }
        session.begin()
        painter.begin()
        return true
    }

    @discardableResult
    func stopViewport() -> Bool {
        guard let session = viewportSession, let painter = viewportPainter else { return false }
        generation &+= 1
        gate.didProcessCharacterEditWithGeometry = nil
        textSystem.preEditObserver = nil
        session.tearDown()
        painter.tearDown()
        viewportSession = nil
        viewportPainter = nil
        return true
    }

    private func didEditViewport(range: NSRange, delta: Int, postEditLength: Int, storage: NSTextStorage?) {
        if postEditLength > Self.viewportMaxUTF16Units {
            guard stopViewport() else { return }
            let limit = policyProvider(languageID)?.reduceAboveUTF16Units
                ?? HighlightingSizePolicy.markdown.reduceAboveUTF16Units
            setMode(.reduced(.documentTooLarge(limitUTF16Units: limit)))
            let clearGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, !isTornDown, generation == clearGeneration else { return }
                clearHighlighterPresentation()
            }
            return
        }
        guard let storage else { return }
        viewportSession?.didEdit(range: range, delta: delta, postSource: storage.mutableString)
        viewportPainter?.didEdit(newRange: range, delta: delta)
    }
}
