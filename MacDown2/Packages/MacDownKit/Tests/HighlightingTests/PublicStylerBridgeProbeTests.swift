import AppKit
import EditorCore
import Neon
import RangeState
import Testing

/// Tests the public presentation seam needed before a production section cache
/// can replace the reduced-mode Markdown fallback. This is not a parser budget
/// or complete highlighter test.
@MainActor
@Suite("Public style bridge for mounted Markdown", .serialized)
struct PublicStylerBridgeProbeTests {
    @Test func mountedEditorAcceptsExternalSemanticTokensAndRefreshesAfterEdit() {
        let original = "# Heading\n\nSome **bold** text.\n"
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let system = store.system(for: identity, initialText: original, configuration: .default)
        let window = mount(system.textView)
        defer {
            store.evict(identity)
            window.contentView = nil
            window.close()
        }
        let interface = TextViewSystemInterface(textView: system.textView) { token in
            [.foregroundColor: token.name == "markup.heading" ? NSColor.systemRed : NSColor.systemBlue]
        }
        let provider = TokenProvider(syncValue: { range in
            let heading = (system.textView.string as NSString).range(of: "Heading")
            return TokenApplication(
                tokens: [Token(name: "markup.heading", range: heading)],
                range: range,
                action: .replace
            )
        }, mainActorAsyncValue: { range in
            let heading = (system.textView.string as NSString).range(of: "Heading")
            return TokenApplication(
                tokens: [Token(name: "markup.heading", range: heading)],
                range: range,
                action: .replace
            )
        })
        let styler = TextSystemStyler(textSystem: interface, tokenProvider: provider)
        styler.invalidate(.all)
        styler.validate(.all)
        let first = renderedRuns(in: system.textView)
        #expect(first.contains { $0.range.location <= 2 && NSMaxRange($0.range) >= 9
                && $0.signature == "c" + colorSignature(NSColor.systemRed)
        })

        let insertion = NSRange(location: 2, length: 0)
        system.textView.insertText("New ", replacementRange: insertion)
        styler.didChangeContent(in: insertion, delta: 4)
        styler.invalidate(.all)
        styler.validate(.all)
        let shifted = (system.textView.string as NSString).range(of: "Heading")
        #expect(shifted.location == 6)
        let second = renderedRuns(in: system.textView)
        #expect(second.contains { $0.range.location <= shifted.location
                && NSMaxRange($0.range) >= NSMaxRange(shifted)
                && $0.signature == "c" + colorSignature(NSColor.systemRed)
        })
        #expect(system.textView.string == "# New Heading\n\nSome **bold** text.\n")
    }

    private func mount(_ view: NSTextView) -> NSWindow {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        view.frame = scroll.bounds
        scroll.documentView = view
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scroll
        window.orderFront(nil)
        scroll.layoutSubtreeIfNeeded()
        return window
    }

    private func renderedRuns(in textView: NSTextView) -> [RenderedRun] {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager else { return [] }
        let origin = content.documentRange.location
        var runs: [RenderedRun] = []
        layout.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, textRange in
            let location = content.offset(from: origin, to: textRange.location)
            let length = content.offset(from: textRange.location, to: textRange.endLocation)
            let signature = RenderedRun.signature(of: attributes)
            if length > 0, !signature.isEmpty {
                runs.append(RenderedRun(range: NSRange(location: location, length: length), signature: signature))
            }
            return true
        }
        return runs
    }

    private func colorSignature(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "%02x%02x%02x", Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
