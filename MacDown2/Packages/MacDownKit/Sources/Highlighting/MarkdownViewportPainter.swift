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
        guard let visible = Self.boundedViewport(in: textSystem) else { return }
        styler.invalidate(.range(visible))
        styler.validate(.range(visible))
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
        return TokenApplication(tokens: session.visibleTokens(), range: clip, action: .replace)
    }

    private static func boundedViewport(in textSystem: EditorTextSystem) -> NSRange? {
        guard let visible = textSystem.visibleUTF16Range,
              visible.length > 0,
              visible.length <= MarkdownSectionCache.windowLimit
        else { return nil }
        return visible
    }
}
