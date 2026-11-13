import AppKit
import EditorCore
import Neon
import RangeState

/// Applies only the current mounted Markdown viewport through Neon's public
/// TextKit 2 styler. Parsing and storage ownership stay with the session.
@MainActor
final class MarkdownViewportPainter {
    private let textSystem: EditorTextSystem
    private let session: MarkdownViewportSession
    private let styler: TextSystemStyler<TextViewSystemInterface>
    private var scrollObserver: NSObjectProtocol?
    private var refreshScheduled = false
    private var isActive = true
    private var lastPaintedRange: NSRange?

    init(textSystem: EditorTextSystem, session: MarkdownViewportSession,
         attributes: @escaping TokenAttributeProvider) {
        self.textSystem = textSystem
        self.session = session
        let interface = TextViewSystemInterface(textView: textSystem.textView, attributeProvider: attributes)
        let provider = TokenProvider(syncValue: { [weak textSystem, weak session] range in
            Self.application(for: range, textSystem: textSystem, session: session)
        }, mainActorAsyncValue: { [weak textSystem, weak session] range in
            Self.application(for: range, textSystem: textSystem, session: session)
        })
        styler = TextSystemStyler(textSystem: interface, tokenProvider: provider)
    }

    func begin() {
        guard isActive else { return }
        attachScrollObserverIfNeeded()
        scheduleRefresh()
    }

    /// `newRange` is post-edit geometry. The styler's validator needs the old
    /// range; updating that state is safe inside the storage delegate, while
    /// applying rendering attributes is deferred until it returns.
    func didEdit(newRange: NSRange, delta: Int) {
        guard isActive else { return }
        let oldLength = newRange.length - delta
        guard newRange.location != NSNotFound, newRange.location >= 0,
              oldLength >= 0
        else {
            styler.invalidate(.all)
            scheduleRefresh()
            return
        }
        styler.didChangeContent(in: NSRange(location: newRange.location, length: oldLength), delta: delta)
        scheduleRefresh()
    }

    func scheduleRefresh() {
        guard isActive, !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            refreshScheduled = false
            guard isActive else { return }
            attachScrollObserverIfNeeded()
            paintVisible()
        }
    }

    func tearDown() {
        guard isActive else { return }
        isActive = false
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
    }

    func paintVisible() {
        guard isActive, !textSystem.textView.hasMarkedText() else { return }
        guard let visible = Self.boundedViewport(in: textSystem) else {
            clearLastPaintedRange()
            return
        }
        if let previous = lastPaintedRange {
            clearPaintedOutside(previous, keeping: visible)
        }
        styler.invalidate(.range(visible))
        styler.validate(.range(visible))
        lastPaintedRange = visible
    }

    /// Layout can temporarily lose the mounted viewport. Remove only the
    /// previously painted bounded range so stale colour cannot survive there.
    private func clearLastPaintedRange() {
        guard let range = lastPaintedRange else { return }
        lastPaintedRange = nil
        clearPaintedRange(range)
    }

    private func clearPaintedOutside(_ previous: NSRange, keeping visible: NSRange) {
        let overlap = NSIntersectionRange(previous, visible)
        guard overlap.length > 0 else {
            clearPaintedRange(previous)
            return
        }
        if previous.location < overlap.location {
            clearPaintedRange(NSRange(location: previous.location, length: overlap.location - previous.location))
        }
        let previousEnd = NSMaxRange(previous)
        let overlapEnd = NSMaxRange(overlap)
        if overlapEnd < previousEnd {
            clearPaintedRange(NSRange(location: overlapEnd, length: previousEnd - overlapEnd))
        }
    }

    private func clearPaintedRange(_ range: NSRange) {
        guard let layout = textSystem.textView.textLayoutManager,
              let content = layout.textContentManager,
              let storage = textSystem.textView.textStorage,
              range.location < storage.length
        else { return }
        let length = min(range.length, storage.length - range.location)
        guard length > 0 else { return }
        let origin = content.documentRange.location
        guard let start = content.location(origin, offsetBy: range.location),
              let end = content.location(start, offsetBy: length),
              let textRange = NSTextRange(location: start, end: end)
        else { return }
        for key in NeonSyntaxHighlighter.highlighterAttributeKeys {
            layout.removeRenderingAttribute(key, for: textRange)
        }
    }

    private func attachScrollObserverIfNeeded() {
        guard scrollObserver == nil,
              let clip = textSystem.textView.enclosingScrollView?.contentView
        else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    private static func application(for requested: NSRange,
                                    textSystem: EditorTextSystem?,
                                    session: MarkdownViewportSession?) -> TokenApplication {
        guard let textSystem, let session,
              let visible = boundedViewport(in: textSystem)
        else { return .noChange }
        let clip = NSIntersectionRange(requested, visible)
        guard clip.length > 0 else { return .noChange }
        return TokenApplication(tokens: session.visibleTokens(in: clip), range: clip, action: .replace)
    }

    private static func boundedViewport(in textSystem: EditorTextSystem) -> NSRange? {
        guard let visible = textSystem.visibleUTF16Range,
              visible.length > 0,
              visible.length <= MarkdownSectionCache.windowLimit
        else { return nil }
        return visible
    }
}
