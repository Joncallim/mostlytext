import Foundation

/// The "Open Recent File" menu (EPIC-22 issue #112, Slice 6c). Split out of
/// `WindowCoordinator.swift` for the same reason
/// `WindowCoordinator+FileTree.swift`'s own `openRecentFolder(_:)` is: a
/// distinct, self-contained menu-action concern.
///
/// Recording into `recentFileDocuments` happens once, centrally, inside
/// `WindowCoordinator.openDocument(at:...)` — the single choke point every
/// real, user-initiated file open routes through (Open…, Open Recent File,
/// Quick Open, sidebar double-click, and Finder/dock/launch-argument opens
/// via `AppDelegate`) — so this file only has to resolve a chosen recent
/// entry back to a real, openable URL. Session restore deliberately does
/// NOT go through `openDocument(at:...)` (it calls
/// `tabStore.newTab(id:document:)` directly instead), so relaunching the
/// app never re-promotes already-open documents to the front of the
/// recent-files list on every launch.
extension WindowCoordinator {
    /// Resolves `url`'s bookmark and opens it, re-promoting it to the front
    /// of the recent-files list the same way `openRecentFolder(_:)` does for
    /// folders (`openDocument(at:...)` records every real open, including
    /// this one). A `nil` resolution (the bookmark's target no longer
    /// exists) silently does nothing — `pruneMissingFiles()` already keeps
    /// the menu itself from offering a dead entry in the first place, so
    /// this is only reachable via a stale menu snapshot from just before a
    /// concurrent deletion.
    /// The returned task completes after document admission and recent-file
    /// publication. Menu callers may discard it; lifecycle tests await it.
    @discardableResult
    func openRecentFile(_ url: URL) -> Task<Void, Never>? {
        guard let resolution = recentFileDocuments.resolve(url) else { return nil }
        // `lexicalURL`, not `accessURL` -- matching `openRecentFolder`'s own
        // choice of `resolution.lexicalURL` for `openFolder`'s primary
        // argument. An independent review of this slice caught this: for a
        // document opened through a symlink alias, `record`/`resolve` always
        // bookmark/resolve against the physical, symlink-*resolved* target,
        // so opening `resolution.accessURL` here would silently open the
        // real target file instead of the alias the user actually clicked --
        // changing its window title, its `fileURL`, and (via
        // `openDocument`'s own `recentFileDocuments.record(url)`) even which
        // path gets re-recorded, all without the user asking for that.
        return Task { await openDocument(at: resolution.lexicalURL) }
    }
}
