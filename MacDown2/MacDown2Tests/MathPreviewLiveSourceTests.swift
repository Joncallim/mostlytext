import AppKit
import EditorCore
import Foundation
@testable import MacDown2
import Testing

/// Native host only: the production provider must read the registered model,
/// actual editor and existing parser rather than a captured SwiftUI value.
@MainActor
struct MathPreviewLiveSourceTests {
    /// Mount the registered TextKit editor directly so these adapter controls
    /// do not race unrelated SwiftUI initial parsing or layout tasks. App-shell
    /// mount/layout acceptance remains a separate native journey.
    static func makeMountedController(text: String) throws -> TextFilterCoordinatorTests.Fixture {
        let fixture = try TextFilterCoordinatorTests.makeController(text: text)
        do {
            let window = try #require(fixture.controller.window)
            let system = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
            window.contentViewController = nil
            let scroll = NSScrollView(frame: window.contentLayoutRect)
            scroll.documentView = system.textView
            window.contentView = scroll
            system.setAwaitingEditorView(false)
            return fixture
        } catch {
            dispose(fixture)
            throw error
        }
    }

    static func dispose(_ fixture: TextFilterCoordinatorTests.Fixture) {
        let window = fixture.controller.window
        window?.isReleasedWhenClosed = false
        window?.orderOut(nil)
        window?.close()
        window?.contentViewController = nil
        fixture.coordinator.controllers.removeAll { $0 === fixture.controller }
    }

    @Test func anEditorOnlyEditCannotBorrowTheUnchangedModelAndPublishedParse() async throws {
        let fixture = try Self.makeMountedController(text: "$x$")
        defer { Self.dispose(fixture) }
        let controller = fixture.controller
        let identity = fixture.tabID.uuidString
        let parse = controller.parseStore.session(for: identity)
        await parse.parseNow("$x$")
        let live = try #require(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity))
        let binding = MathPreviewSourceBinding(stamp: live.stamp, source: live.publishedText)
        #expect(binding.isCurrent(live))
        let editor = try #require(controller.editorStore.existingSystem(for: identity))
        editor.textView.string = "$y$"
        let changed = try #require(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity))
        #expect(changed.modelText == "$x$" && changed.publishedText == "$x$")
        #expect(changed.editorText == "$y$")
        #expect(!binding.isCurrent(changed))
    }

    @Test func aNontextGenerationChangeAndParserReplacementInvalidateOldAuthority() async throws {
        let fixture = try Self.makeMountedController(text: "$x$")
        defer { Self.dispose(fixture) }
        let controller = fixture.controller
        let identity = fixture.tabID.uuidString
        let parse = controller.parseStore.session(for: identity)
        await parse.parseNow("$x$")
        let live = try #require(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity))
        let binding = MathPreviewSourceBinding(stamp: live.stamp, source: live.publishedText)
        controller.model.tabStore.updateActiveDocument { $0.updatingText($0.text).markClean() }
        let saved = try #require(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity))
        #expect(saved.publishedText == live.publishedText && saved.stamp.parseIdentity == live.stamp.parseIdentity)
        #expect(saved.stamp.mutationGeneration != live.stamp.mutationGeneration)
        #expect(!binding.isCurrent(saved))
        controller.parseStore.evict(identity)
        #expect(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity) == nil)
        await controller.parseStore.session(for: identity).parseNow("$x$")
        let replacement = try #require(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity))
        #expect(replacement.stamp.parseIdentity != live.stamp.parseIdentity)
        #expect(!binding.isCurrent(replacement))
    }

    @Test func removedWindowsAndUnknownTabsCannotCreateFreshAuthority() async throws {
        let fixture = try Self.makeMountedController(text: "$x$")
        defer { Self.dispose(fixture) }
        let controller = fixture.controller
        let identity = fixture.tabID.uuidString
        await controller.parseStore.session(for: identity).parseNow("$x$")
        #expect(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity) != nil)
        let foreign = UUID().uuidString
        #expect(fixture.coordinator.mathLiveSource(in: controller.model, identity: foreign) == nil)
        #expect(controller.parseStore.existingSession(for: foreign) == nil)
        #expect(controller.editorStore.existingSystem(for: foreign) == nil)
        fixture.coordinator.controllers = []
        #expect(fixture.coordinator.mathLiveSource(in: controller.model, identity: identity) == nil)
    }
}
