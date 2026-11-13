import AppKit
import EditorCore
import Neon

/// Optional integration seam for the bounded mounted Markdown owner. The app
/// keeps this off until the complete Release budget and native gate qualify.
extension NeonSyntaxHighlighter {
    @discardableResult
    func startViewport() -> Bool {
        guard !isTornDown, viewportModeEnabled, languageID == "markdown",
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
        gate.didProcessCharacterEditWithGeometry = { [weak session, weak painter, weak storage] range, delta, _ in
            guard let storage else { return }
            session?.didEdit(range: range, delta: delta, postSource: storage.mutableString)
            painter?.didEdit(newRange: range, delta: delta)
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
}
