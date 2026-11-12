import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
import JSONSupport
@testable import MacDown2
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Testing
import Themes
import Workspace

/// Regression coverage for the mounted editor's final async-find publication
/// guard. The coordinator-only test proves the revision changes; this test
/// calls the production `applyFindHighlights` method against a real mounted
/// `EditorView` and proves the guard protects the live selection.
@MainActor
@Suite("Document editor find navigation")
struct DocumentEditorFindNavigationTests {
    private static func waitForSignal(
        _ stream: AsyncStream<Void>,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private static func makeCoordinator() -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    private static func makeSplit(
        model: WorkspaceModel,
        tab: WorkspaceTab,
        text: String,
        editorStore: EditorTextSystemStore,
        findStore: EditorFindModelStore
    ) -> DocumentEditorSplitView {
        DocumentEditorSplitView(
            model: model,
            document: tab.document,
            tab: tab,
            identity: tab.id.uuidString,
            text: .constant(text),
            editorStore: editorStore,
            findStore: findStore,
            highlightStore: SyntaxHighlightStore(registry: GrammarRegistry()),
            parseStore: MarkdownParseStore(debounce: .zero),
            jsonAnalysisStore: JSONAnalysisStore(debounce: .zero),
            themeController: ThemeController(),
            scrollController: ScrollSyncController(),
            outlineController: OutlineController()
        )
    }

    /// Hosts `rootView` in a real key window so the editor mounts through
    /// `makeNSView`; the caller closes the window.
    private static func mountInWindow(_ rootView: AnyView) -> (NSHostingView<AnyView>, NSWindow) {
        let hosting = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    /// The Find bar wired exactly as the split view wires it: published
    /// matches go through the production `applyFindHighlights`, then the
    /// returned stream yields once per publication.
    private static func makeFindBar(
        findModel: EditorFindModel,
        text: String,
        system: EditorTextSystem,
        split: DocumentEditorSplitView,
        coordinator: WindowCoordinator
    ) -> (FindBarView, AsyncStream<Void>) {
        let published = AsyncStream<Void>.makeStream()
        let findBar = FindBarView(
            model: findModel,
            recentQueries: split.findStore.recentQueries,
            onRememberQuery: { split.findStore.rememberQuery($0) },
            onClearRecentQueries: { split.findStore.clearRecentQueries() },
            text: text,
            resolvedText: { text },
            resolvedSelection: { system.selectedRange },
            initialAnchor: 0,
            onMatchesChanged: { reveal, navigationToken in
                split.applyFindHighlights(
                    findModel,
                    reveal: reveal,
                    navigationToken: navigationToken,
                    navigationCoordinator: coordinator
                )
                published.continuation.yield(())
            },
            onNavigationIntent: { coordinator.folderSearchNavigationDidChange() },
            onClose: { split.closeFindBar(findModel) },
            onReplace: { _ in },
            onSelectAll: { _ in }
        )
        return (findBar, published.stream)
    }

    /// The tab's cached Find model, activated with `query` and with its
    /// matches computed against `text`.
    private static func activeFindModel(
        in findStore: EditorFindModelStore,
        identity: String,
        query: String,
        text: String
    ) async -> EditorFindModel {
        let findModel = findStore.model(for: identity)
        findModel.query = query
        findModel.isActive = true
        #expect(await findModel.updateMatches(in: text, preferringLocationNear: 0))
        return findModel
    }

    @Test func staleFindCompletionCannotMoveNewerFolderSearchSelection() async throws {
        let coordinator = Self.makeCoordinator()
        let model = coordinator.makeWindowModel()
        let text = "old result\nnew result"
        model.tabStore.newTab(document: FileDocument(text: text))
        let tab = try #require(model.tabStore.activeTab)
        let identity = tab.id.uuidString
        let editorStore = EditorTextSystemStore()
        let findStore = EditorFindModelStore()
        let split = Self.makeSplit(model: model, tab: tab, text: text, editorStore: editorStore, findStore: findStore)
        let (_, window) = Self.mountInWindow(AnyView(
            EditorView(
                text: .constant(text),
                identity: identity,
                configuration: .default,
                store: editorStore
            )
        ))
        defer { window.contentView = nil; window.close() }

        let staleModel = EditorFindModel(query: "old")
        staleModel.isActive = true
        #expect(await staleModel.updateMatches(in: text))
        let staleToken = coordinator.folderSearchNavigationDidChange()

        let currentModel = EditorFindModel(query: "new")
        currentModel.isActive = true
        #expect(await currentModel.updateMatches(in: text))
        let currentToken = coordinator.folderSearchNavigationDidChange()

        let system = try #require(editorStore.existingSystem(for: identity))
        #expect(system.textView.window === window)
        #expect(!system.isDetachedFromEditorView)
        split.applyFindHighlights(
            currentModel,
            navigationToken: currentToken,
            navigationCoordinator: coordinator
        )
        let selectedByCurrent = system.selectedRange
        #expect(selectedByCurrent == NSRange(location: 11, length: 3))
        #expect(system.textView.window === window)
        #expect(!system.isDetachedFromEditorView)
        split.applyFindHighlights(
            staleModel,
            navigationToken: staleToken,
            navigationCoordinator: coordinator
        )
        #expect(system.selectedRange == selectedByCurrent)
    }

    @Test func cachedFindBarRemountRefreshDoesNotRevealOverNewerSelection() async throws {
        let coordinator = Self.makeCoordinator()
        let model = coordinator.makeWindowModel()
        let text = "old result\nnew result"
        model.tabStore.newTab(document: FileDocument(text: text))
        let tab = try #require(model.tabStore.activeTab)
        let identity = tab.id.uuidString
        let editorStore = EditorTextSystemStore()
        let findStore = EditorFindModelStore()
        let findModel = await Self.activeFindModel(in: findStore, identity: identity, query: "old", text: text)
        // Capture the activation revision before the view remount. This is
        // the token `WindowCoordinator.toggleFind()` now stores; the later
        // folder navigation must make it stale without a delayed onAppear
        // callback minting a replacement intent.
        let activationToken = coordinator.folderSearchNavigationDidChange()
        findModel.pendingRevealNavigationToken = activationToken

        let split = Self.makeSplit(model: model, tab: tab, text: text, editorStore: editorStore, findStore: findStore)
        let editor = EditorView(
            text: .constant(text),
            identity: identity,
            configuration: .default,
            store: editorStore
        )
        let (hosting, window) = Self.mountInWindow(AnyView(editor))
        defer { window.contentView = nil; window.close() }

        let system = try #require(editorStore.existingSystem(for: identity))
        #expect(system.textView.window === window)
        let newerFolderSelection = NSRange(location: 11, length: 3)
        coordinator.folderSearchNavigationDidChange()
        system.revealSelection(utf16Range: newerFolderSelection, flash: false)
        let (findBar, published) = Self.makeFindBar(
            findModel: findModel,
            text: text,
            system: system,
            split: split,
            coordinator: coordinator
        )
        let callbackObserved = Task {
            await Self.waitForSignal(published)
        }
        hosting.rootView = AnyView(
            VStack(spacing: 0) {
                findBar.environment(\.windowCoordinator, coordinator)
                editor
            }
        )
        hosting.layoutSubtreeIfNeeded()
        #expect(await callbackObserved.value)

        let currentSystem = try #require(editorStore.existingSystem(for: identity))
        #expect(currentSystem === system)
        #expect(currentSystem.textView.window === window)
        #expect(!currentSystem.isDetachedFromEditorView)
        #expect(currentSystem.selectedRange == newerFolderSelection)
        #expect(findModel.pendingRevealNavigationToken == nil)
    }
}
