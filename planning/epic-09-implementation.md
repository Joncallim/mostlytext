# EPIC-09 Implementation Record — Folder browser: lazy file tree, FS watching, CRUD

> **Issue:** #10 — [EPIC-09] Folder browser: lazy file tree, FS watching, CRUD
> **High-level spec:** `planning/epics/EPIC-09-folder-browser.md` (scope/acceptance are binding, including the #28 amendment that the sidebar — and therefore the folder root — is per window).
> **Status:** Implemented and merged via PR #38 (`e60efb0`). This document is
> retained as the implementation record for the delivered Epic 9 work.
> **Branch:** `epic/09-folder-browser` → merged into `master`.
> **Depends on:** E01 as built (`FileDocument`, `FileFormatRegistry`, `FileStore`), E02 as built (`WorkspaceModel`, `SidebarSection`, `WorkspaceStateStoring`), E03 as built (native `NSWindow` tabs, `WindowCoordinator`, per-window `WorkspaceModel`), E08 as built (the sidebar `List` this epic has to share).
> **Historical implementation pipeline:** the plan was written as a hand-off
> contract and subsequently implemented, independently reviewed, remediated,
> and merged. The sections below describe the decisions and contracts that the
> shipped implementation follows.
>
> **No new third-party dependencies.** The `FileTree` target already exists in `Package.swift` with `dependencies: ["FileCore"]`, already has a `FileTreeTests` test target, and is already listed under the `MacDown2` app target in `project.yml` (E00 scaffolding). **No `Package.swift` change, no `project.yml` change, no `ci.yml` change.**
>
> **Pre-flight:** `master` is green at `61cad7c` — `swiftformat --lint MacDown2` reports `0/149 files require formatting` and `swiftlint lint --strict MacDown2` reports `0 violations`. No drive-by lint commit needed.
>
> **Two platform facts in this plan were checked, not assumed** (Swift 6.3.3 / macOS 26, `-swift-version 6 -strict-concurrency=complete`), because the design turns on them and both are commonly mis-remembered. A nonisolated `deinit` on a `@MainActor` class **can** read isolated stored properties but **cannot** call an isolated method (D5). `bookmarkData(options: .withSecurityScope)` **succeeds unsandboxed**, resolves, and `startAccessingSecurityScopedResource()` returns `true` (D14). Earlier drafts of both sections said the opposite; the corrections are recorded inline so a reviewer does not have to re-derive them.
>
> **⚠️ This is the first epic to add real concurrency since E07.** `DispatchSource` handlers run off the main actor and hop back onto it. CI runs Xcode 26.0.1, which has rejected concurrency code the newer local toolchain accepted (E07). **Push and read CI before calling any of §4.5 verified** — see §9.

---

## 1. Ground rules (binding, carried from E00–E08)

1. **macOS 26.0 only. No availability checks.** Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings.
2. **Package holds the logic; the app holds glue.** Sorting, filtering, diffing, flattening, name uniquing, and every CRUD precondition are pure, `Sendable`, headless, and tested under `swift test`. The app target owns only: view code, alerts, menu commands, and the wiring between the sidebar and the window/tab pool.
3. **Same architecture rule as `FileCore` (the epic says so explicitly): pure synchronous model core, async edges.** There are exactly **two** IO seams in this module — `DirectoryReading` (list a directory) and `FileSystemMutating` (create/move/copy/trash) — plus the watcher. Everything else is a function of `[DirectoryEntry]`.
4. **Native controls, native behaviors.** `List` rows, `.contextMenu`, `.draggable`/`.dropDestination`, `NSAlert` for destructive confirms, `FileManager.trashItem` for delete. No custom outline widget, no re-implementation of drag arbitration.
5. **Tests are Swift Testing (`@Test`/`#expect`)**, not XCTest — except `MacDown2UITests`, where `XCUIApplication`-hosted bundles cannot `import Testing` (verified during E07; not a convention violation).
6. **Graceful totality.** Every input produces a defined state. A missing root, an unreadable directory, a folder emptied *by the filter* rather than by its contents, a drop onto a file, a rename to a name that already exists, a move into a folder's own subtree — all have named, tested outcomes. There is no "this shouldn't happen" branch.
7. **Tabs are native `NSWindow` tabs.** One window = one document. "Opens in a tab" means `WindowCoordinator.openDocument(at:)`, which already dedupes across every window and selects the existing tab when the file is already open.
8. **Unsandboxed (migration-plan D7), modeled on security-scoped URLs.** See D14 — this constrains *how* we persist roots, and the plan takes the constraint seriously rather than writing `.withSecurityScope` into code that cannot use it.

---

## 2. Ground truth: what exists, what is missing, what collides

### 2.1 The `FileTree` module is a one-line stub and everything around it is already wired

```swift
// Sources/FileTree/FileTree.swift — as built
public enum FileTree { public static let moduleName = "FileTree" }
```

`Package.swift` already declares the product, the target (`dependencies: ["FileCore"]`) and `FileTreeTests`; `project.yml` already lists `FileTree` under the app target. This epic fills the stub in. **If a `Package.swift` or `project.yml` diff appears in this PR, something has gone wrong** (§6).

### 2.2 `Open Folder…` already exists and already does nothing

`WorkspaceCommands` binds ⌘⇧O to `coordinator?.keyModel?.openFolder()`, which sets `WorkspaceModel.folderURL` (per window, `private(set)`). `SidebarView.folderContent` renders exactly one line — `Text(folderURL.lastPathComponent)` — or `"No folder opened"`. So the command, the panel (`NSFilePanelProvider.chooseFolder()`, `canChooseDirectories = true`), the per-window storage, and the sidebar section all exist. **This epic does not add "open a folder"; it adds everything the opened folder was supposed to do.**

What is missing on `WorkspaceModel`: a way to set the root *without* a panel (needed by recents and by "reveal a file outside the root"), and any persistence of the root at all.

### 2.3 ⚠️ Collision: the sidebar `List` has exactly one `selection` binding, and E08 owns it

```swift
// SidebarView.swift — as built
List(selection: $outlineController.selectedItemID) { ... }   // Binding<Int?>
```

`List(selection:)` takes **one** `Hashable` type for the whole list. E08 bound it to `OutlineItem.id`, which is an `Int` ordinal. Folder rows need to be selectable in the *same* `List` — they are rows of the same list, in a sibling `Section` — and their identity is a URL, not an ordinal. There is no way to have two selection bindings on one `List`.

This is not a detail that can be discovered during implementation and patched: it changes the type at the top of `SidebarView`, it changes what `.tag(...)` carries on every row including E08's, and it changes what `.onKeyPress(.return)` dispatches on. The resolution is **D8**. It is deliberately contained in the app target so that neither `OutlineUI` nor `FileTree` learns the other exists.

### 2.4 ⚠️ Blocker for acceptance box 3: `FileDocument` cannot be renamed

Acceptance: *"Renaming an open file updates tab title + save target."*

```swift
// FileCore/FileDocument.swift — as built
public let id: String          // fileURL.absoluteString for file-backed documents
public var fileURL: URL?
public let format: FileFormat  // derived from fileURL's path extension at init
```

`fileURL` is settable, so the *save target* can be moved. `id` and `format` cannot. Consequences of setting only `fileURL`:

- **`format` goes stale.** Rename `notes.md` → `notes.txt` and the document keeps `markdown`: the preview stays a Markdown preview, tree-sitter stays on the markdown grammar, and E08's outline stays populated. `WindowController.updateTitleAndEditedState()` already re-attaches the highlighter when `format.highlightLanguageID` changes — that machinery works, it just never fires, because `format` never changes.
- **`id` goes stale.** `id` is the `RecoveryBuffer` key and the `documentID` in `WindowCoordinator.saveSession`. A dirty renamed document autosaves under its old path-derived key. No user-visible symptom today (recovery restore is keyed by `untitledDocumentID`, which is nil for file-backed documents), but it is a latent inconsistency and it costs one method to not have.

The window **title** is fine either way: `updateTitleAndEditedState()` reads `model.activeDocument?.fileURL?.lastPathComponent` on a 250 ms poll, so the title follows `fileURL` within one tick. (That tick is why the UI test in §7 must wait rather than assert immediately.)

Fix in D12: relax `id` and `format` to `public private(set) var` and add `FileDocument.renamed(to:)`. Own commit, own tests, reviewable separately from the folder browser.

### 2.5 `FileFormat.format(for:in:)` returns `nil` for extensionless files

```swift
let pathExtension = url.pathExtension.lowercased()
guard !pathExtension.isEmpty else { return nil }
```

So `README`, `LICENSE`, `Makefile`, and `Dockerfile` are **not** "supported files" by the registry's own definition. This decides the behavior of the epic's *"Supported files only"* filter toggle for a very common case in exactly the folders a developer would open. Plan: the registry *is* the definition, so the filter hides them — and the filter therefore ships **off by default**, so it is always a deliberate user action. Flagged as open decision §10.1.

### 2.6 The watcher/E18 boundary, stated precisely

The #28 amendment: *"The `DispatchSource` watching in this epic covers the **directory tree UI only**; watching open documents for external changes (reload/conflict) is **E18**."* Two of E09's acceptance boxes are nonetheless about open documents:

> - Deleting the file open in the active tab offers close/discard flow; no crash
> - Renaming an open file updates tab title + save target

These are not in conflict, because **the epic also owns in-app CRUD**. The line is the *origin of the change*, not the effect:

| Change originates in | Tree updates | Open document reacts | Owner |
|---|---|---|---|
| The sidebar's own Delete / Rename / Move | yes | **yes — E09** | E09 |
| Finder, `git checkout`, another app | yes (watcher) | **not in E09** | tree: E09 · document: **E18** |

E09 implements the document consequences for the paths it triggers itself, where it knows old→new with certainty and needs no heuristics. It does **not** implement external-change detection for open documents — including for documents that happen to be inside the folder root. E18 generalizes that later for *all* open documents, root or not, and must not have to depend on this module (D11).

### 2.7 Related open issues this epic touches but does not close

- **#34 — sidebar layout caches go stale across windows.** Each window's `WorkspaceModel` hydrates `sectionOrder`/`sectionExpanded` from the shared `UserDefaults` suite once at init and never re-reads, so a second window reorders using stale input. E09 adds three more persisted view preferences (hidden files, supported-only, folders-first) plus a recent-roots list. **Adding them the same way would ship the same bug four more times.** D7 is how this plan avoids that, and it is the *shared observable store* option that #34 itself lists. It does not retrofit `sectionOrder`/`sectionExpanded`, because #34 says the app-wide-vs-per-window question must be answered first.
- **#35 — non-Markdown documents are still fully Markdown-parsed.** Untouched here. Opening a `.py` file from the folder tree runs a full swift-markdown parse exactly as opening it from ⌘O does today.

---

## 3. Key architectural decisions (review anchors — do not silently deviate)

### D1 — `FileTree` depends on `FileCore` and nothing else
Not `Workspace`, not `EditorCore`, not `OutlineUI`, not `Preview`. The module receives a root URL, a filter, and a set of supported extensions; it publishes rows, availability, and CRUD outcomes. Tabs, windows, alerts, and menus are the app target's business. This keeps the module headless-testable and keeps `Package.swift` unchanged. `FileCore` is needed only for `FileFormatRegistry` (the supported-extension set) — and even that is passed in as a `Set<String>`, so the coupling is one initializer parameter, not a dependency inside the pure functions.

### D2 — Two IO seams, both injected; everything else is pure
```
DirectoryReading      →  list one directory  →  [DirectoryEntry]
FileSystemMutating    →  create / move / copy / trash
DirectoryWatching     →  tell me when a directory changed (no payload)
```
Filtering, sorting, diffing, flattening to rows, name uniquing, and every CRUD precondition are pure functions of `[DirectoryEntry]` and `String`. **Consequence for tests:** sort/filter/diff/naming tests need no temp directory and no `async`; only the reader, the mutator, and the real watcher touch disk. Any test that creates a temp directory to assert a sort order is testing the wrong seam.

### D3 — Lazy loading is per-directory load state keyed by URL
`FileTreeModel` holds `expanded: Set<URL>`, `children: [URL: DirectoryLoadState]`, and `watchers: [URL: DirectoryWatcher]`. Expanding a directory transitions `.notLoaded → .loading → .loaded([DirectoryEntry])` (or `.failed`). Collapsing **keeps the cached children and drops the watcher** — re-expanding is then instant and correct, because the focus rescan (D6) and the parent's own watcher cover anything that changed while it was closed. Loading a directory never loads its grandchildren; a directory's row shows a disclosure chevron based on `isDirectory` alone, never on "does it have children" (which would cost a listing per row).

### D4 — Node identity is the standardized file URL, and it is normalized at exactly one place
`DirectoryEntry.url` is always `standardizedFileURL`, and always constructed with the correct `isDirectory` flag. This is not pedantry:

- `URL` is `Hashable` on its **string**, so `file:///a/b` and `file:///a/b/` are different keys. Mix the two and a directory can be expanded and collapsed at the same time.
- `standardizedFileURL` removes `.`/`..` and does **not** resolve symlinks. **Never call `resolvingSymlinksInPath`.** Resolving would relocate a symlinked folder's children under the target's path, breaking the parent→child relationship the tree is built from.

Normalization happens in `DirectoryEntry.init` and nowhere else, so there is one place to get it right and one test to pin it.

Unlike E08's ordinals, URLs are stable across re-scans, so **collapse state and selection need no identity remap** — the `OutlineIdentityMap` machinery has no counterpart here. Renaming *does* change identity, deliberately: an in-app rename carries old→new and re-keys `expanded`/`children`/`watchers` explicitly (D10); an external rename arrives as remove+add and the node collapses. That is the honest outcome and it matches every file browser on the platform.

### D5 — One `DispatchSource` per watched directory; the fd closes in the cancel handler; the watcher is **not** `@MainActor`
```swift
let fd = open(url.path, O_EVTONLY)
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: queue)
source.setCancelHandler { close(fd) }     // ← the ONLY close. Never close before cancel.
source.setEventHandler { ... }
source.resume()
```
Two things are load-bearing:

1. **`close(fd)` belongs in the cancel handler and nowhere else.** Closing before the source finishes cancelling is a use-after-close on a descriptor the kernel may still be delivering events for, and the number it leaves behind can be reused by an unrelated `open` in the same process. `DispatchSource.cancel()` is idempotent and the cancel handler runs at most once, so this closes exactly once.
2. **`DirectoryWatcher` is a plain `final class`, not `@MainActor`.** The reason is narrower than "a main-actor `deinit` can't see its own state", which is **not true** — verified on the local toolchain (Swift 6.3.3, `-swift-version 6 -strict-concurrency=complete`): a nonisolated `deinit` on a `@MainActor` class *can* read isolated stored properties and call nonisolated methods on them, so `deinit { source.cancel() }` compiles. What it **cannot** do is call an isolated instance method — `deinit { cancelIsolated() }` fails with `#ActorIsolatedCall`. That is the trap: the natural refactor (a `cancel()`/`tearDown()` helper called from both the explicit path and `deinit`) stops compiling the moment the type is main-actor-isolated, and the usual escape — `Task { @MainActor in self.cancel() }` in `deinit` — resurrects `self` and never runs. Keeping the fd-owning type non-isolated makes plain RAII expressible, so "no fd leaks" is a property of the type rather than of every call site. Explicit `tearDown()` from `windowWillClose` stays as belt-and-braces.

**Watch scope is the root plus every expanded directory** — that is the acceptance criterion ("watching scoped to expanded folders"), and it is what bounds the fd count. Instrumentation for the test: `FileTreeModel.watchedDirectoryCount`. The criterion "no fd leaks" is tested as *that count returns to zero* after collapse-all and after `tearDown()`, plus a churn test that expands/collapses repeatedly and asserts the count stays bounded — not by shelling out to `lsof`.

### D6 — A filesystem event is a hint, not a payload: re-list, diff, apply
`DispatchSource` tells you a directory changed, not what changed. So every event does: re-list → `FileTreeDiff.diff(old:new:)` → apply. The diff is not an optimization detail, it is what makes the design viable:

- The watcher fires on **any** write inside the directory, including MacDown's own atomic save writing `.notes.md.tmp-<uuid>` and replacing `notes.md`. That is several events per save, on a directory whose *listing* is unchanged. Without a diff, every keystroke-triggered save would rebuild and re-render the tree.
- A removed **directory** needs its watcher cancelled and its cached subtree evicted. Only the diff knows which entries left.

Events are coalesced per directory on a **250 ms** debounce before the re-list (comfortably inside the "< 1 s" acceptance box, and enough to swallow a `git checkout`'s burst). Additionally, `windowDidBecomeKey` triggers `rescanExpandedDirectories()` — the safety net for events dropped while the app was inactive or App Nap throttled the queue. Both paths are the same re-list-and-diff, so they are idempotent and may race harmlessly.

The event handler runs on a background queue and hops to the main actor to apply. The re-listing itself must happen **off** the main actor — a 10k-entry directory takes long enough that doing it inline would drop frames.

### D7 — Filters, sort, and recents are app-wide state in **one shared observable object**, not per-window caches
`FileTreePreferences` is a single `@MainActor @Observable` instance created once by `AppDelegate` and injected into every `WindowController`. It writes through to `UserDefaults` on mutation and is read directly — there is no per-window cached copy, therefore nothing to go stale, therefore #34's failure mode cannot occur for this state.

This is a deliberate, narrow application of the fix #34 proposes ("a shared observable store object"). It does **not** retrofit `sectionOrder`/`sectionExpanded`, because #34 is explicit that the app-wide-vs-per-window product question has to be answered before that state moves. What it does do is refuse to add four more instances of a bug that is already on the tracker (§10.9).

The **root** stays per window (`WorkspaceModel.folderURL`), per the #28 amendment. Preferences are app-wide; the thing being browsed is not.

### D8 — The sidebar gets one selection type; both modules stay ignorant of each other
```swift
// App target — MacDown2/SidebarSelection.swift
enum SidebarSelection: Hashable {
    case outline(Int)      // OutlineItem.id
    case file(URL)         // DirectoryEntry.url
}
```
`SidebarView` binds `List(selection:)` to a `Binding<SidebarSelection?>` whose getter/setter project into `outlineController.selectedItemID` and `fileTreeModel.selectedURL`. `OutlineUI`'s public API does not change; `FileTree`'s does not mention outlines. `.onKeyPress(.return)` switches on the case: `.outline` → `outlineController.activate(id)`, `.file` → open in a tab (or expand, for a directory).

Rejected alternatives, for the record: two `List`s (impossible inside one sidebar list); leaving `List(selection:)` on outline ordinals and hand-rolling folder-row highlighting (loses native arrow-key traversal, which acceptance box 5 of *E08* already established as the bar).

### D9 — `FolderAvailability` is a typed enum with six cases, and "empty" is two of them
| Case | Condition | Sidebar shows |
|---|---|---|
| `.noRoot` | no folder opened in this window | "No folder opened" + Open Folder… hint |
| `.loading` | first listing of the root in flight | a progress row (not an empty state — no flash) |
| `.rootUnreadable(reason:)` | root missing, not a directory, or `EACCES` | the reason + "Choose Another Folder…" |
| `.empty` | root listed, genuinely contains nothing | "Empty folder" |
| `.emptyAfterFilter` | root has entries, **filters hid all of them** | "No matching files" + "Clear filters" |
| `.ready` | ≥1 visible row | the tree |

`.emptyAfterFilter` earns its own case because the alternative is a user turning on "Supported files only" in a folder of `.py` files and concluding the app is broken. Collapsing it into `.empty` would be the same class of mistake E08 avoided by splitting `.noHeadings` from `.notParsed`.

### D10 — CRUD = pure naming/validation + a thin mutating seam; the model re-keys its own state on rename
Every precondition is decided before any syscall, by a pure function that returns a typed error:

- empty name, name containing `/` or `:`
- name collides with a sibling — compared **case-insensitively**, because APFS is case-insensitive by default, and **excluding the item's own current name**, because `notes.md` → `Notes.md` is a legal case-only rename that a naive check rejects
- move into the source's own subtree — compared by **path components**, not string prefix (`/a/foo` is not inside `/a/foobar`)
- move to the directory it is already in (no-op, not an error)

Uniquing follows Finder: `untitled.md` → `untitled 2.md`; duplicate is `notes.md` → `notes copy.md` → `notes copy 2.md`. Delete is `FileManager.trashItem(at:resultingItemURL:)` behind an `NSAlert` confirm — never `removeItem`.

On a successful in-app rename or move, `FileTreeModel.itemWasRenamed(from:to:)` re-keys `expanded`, `children`, and `watchers` for the moved node **and every cached descendant path**, so an expanded folder stays expanded when it is renamed. The watcher's own event for the same change then diffs to nothing (D6), which is exactly why both paths being idempotent matters.

### D11 — In-app CRUD drives the open-document consequences; external changes do not (E18 boundary)
`WindowCoordinator` gets two intents, both driven only from the sidebar's own operations (§2.6):

- `documentWasRenamed(from:to:)` — find the tab (across all windows) whose `document.fileURL` standardizes to `from`, apply `FileDocument.renamed(to:)`. Title, save target, format, highlighter, and preview routing all follow from that one call (D12).
- `documentFileWasDeleted(at:)` — find the tab; **clean** documents close their window (there is nothing to discard, and an OK-only alert is noise); **dirty** documents raise one alert — *Save As… / Close Without Saving / Keep Open* — with "Keep Open" leaving the document exactly as it was, so ⌘S recreates the file.

The tab lookup and the clean/dirty verdict are a pure, testable intent on `TabStore` (§4.6); only the alert lives in the app target. The watcher does **not** call either of these.

### D12 — `FileDocument.renamed(to:)`, and `id`/`format` relax from `let` to `private(set) var`
```swift
// FileCore/FileDocument.swift
public private(set) var id: String        // was: let
public private(set) var format: FileFormat // was: let

/// Re-points a file-backed document at a moved/renamed file. Preserves `text`,
/// `state`, and `lastKnownModificationDate`; recomputes `id` and `format` from
/// the new URL exactly as `init` would (§2.4). No IO.
public func renamed(to url: URL) -> FileDocument
```
Source-compatible for every existing reader. This is the whole of acceptance box 3 and it is one method; the alternative — mutating `fileURL` alone — silently leaves a `.txt` file being previewed and highlighted as Markdown. Lands as its own commit before any folder-browser code (§8.1).

Deliberately **not** in scope: making `saveAs(_:)` re-key `id` the same way. It has the same staleness, it predates this epic, and changing it moves the `RecoveryBuffer` key for untitled documents mid-flight — a session-restore concern that wants its own change. Flagged in §10.10.

### D13 — The per-window root persists in `TabRecord` as bookmark `Data?`; **no session version bump**
`TabRecord` gains `folderRootBookmark: Data?`. Swift's synthesized `Codable` decodes a missing optional key as `nil`, so **existing `session.json` files still load** and `WorkspaceSession.currentVersion` stays `1`. Bumping it would make `loadSession()`'s `guard session.version == currentVersion` discard every existing user's open tabs — a data-loss change dressed as bookkeeping. Do not bump it.

Bookmarks rather than paths: a bookmark survives the folder being moved or renamed between launches, which a stored path does not. Security-scoped bookmarks specifically — see D14, they work unsandboxed and cost nothing extra.

### D14 — Security-scoped bookmarks are used **for real**, today; sandboxing then becomes an entitlement change only
Migration-plan D7: unsandboxed for now, *"`FileTreeModel` still designed around security-scoped URLs so sandboxing is additive later."*

An earlier draft of this section assumed `.withSecurityScope` throws without the sandbox entitlement and proposed a no-op seam instead. **That is wrong** — verified on the deployment target (macOS 26, Swift 6.3.3), unsandboxed:

```
dir.bookmarkData(options: .withSecurityScope)                → 736 bytes, no throw
URL(resolvingBookmarkData:options:[.withSecurityScope], …)   → resolves, stale == false
url.startAccessingSecurityScopedResource()                   → true
```

So the migration plan's aspiration is directly achievable now, and the plan takes it literally rather than stubbing it:

- Roots persist as `bookmarkData(options: .withSecurityScope)` (recents **and** `TabRecord.folderRootBookmark`).
- They resolve with `.withSecurityScope`, and a `bookmarkDataIsStale == true` resolution re-saves the bookmark (the folder moved).
- Every use of a resolved root is wrapped in a real RAII scope:

```swift
/// Balanced `startAccessingSecurityScopedResource()` / `stopAccessing…`.
/// `started` is checked because `stopAccessing…` must NOT be called when
/// `start` returned false — the calls are reference-counted and an unbalanced
/// stop decrements someone else's claim.
public final class FolderAccessScope {
    public init(url: URL)      // started = url.startAccessingSecurityScopedResource()
    deinit                     // if started { url.stopAccessingSecurityScopedResource() }
}
```

Turning the sandbox on later is then an entitlement change plus an open-panel-grants-access review — no bookmark format migration, no call sites to find. Note the scope object is a class with a `deinit`, not `~Copyable`: it must outlive the expression that created it and be released deterministically when the root changes.

**Do not** wrap freshly-panel-chosen URLs in a scope before they have been round-tripped through a bookmark — an un-bookmarked URL returns `false` from `start`, which is correct and must not be treated as an error.

### D15 — Rows are flattened **and stored**, not computed per body evaluation
`FileTreeModel.rows: [FileTreeRow]` is a stored property, recomputed only on structural change (expand, collapse, diff applied, filter changed, root changed). E08's `OutlineTree.visibleRows` is computed inside `SidebarView.body` and that is fine at outline scale; at 10 000 entries a per-body-evaluation flatten is the quadratic trap. `List` + `ForEach` stays lazy in AppKit's backing view, so only the flatten needs guarding — but it needs guarding.

Do **not** reach for `List(_:children:)`/`OutlineGroup`: the folder section lives inside a `DisclosureGroup` inside a `Section` inside the sidebar's existing `List`, and a `List` cannot nest in a `List`. Flatten-with-depth is the same shape E08 already renders (`OutlineRow(item:depth:)`), which is the point.

---

## 4. Architecture

### 4.1 Module boundary & dependency graph

```
        FileCore  ────────────────┐
   (FileFormatRegistry,           │
    FileDocument.renamed)         ▼
                              ┌─────────┐
                              │FileTree │   ← this epic (fills the stub)
                              └────┬────┘
                                   │ DirectoryEntry / FileTreeRow /
                                   │ FolderAvailability / FileTreeModel /
                                   │ FileTreePreferences / RecentFolderRoots
                                   ▼
  Workspace ───────────▶  ┌──────────────────┐  ◀────────── OutlineUI
  (WorkspaceModel root,   │   app target     │             (unchanged API)
   TabStore intents,      │  SidebarView     │
   TabRecord bookmark)    │  SidebarSelection│
                          │  WindowController│
                          │  WindowCoordinator
                          │  WorkspaceCmds   │
                          └──────────────────┘
```

`FileTree` imports `Foundation`, `Observation`, `Dispatch`, and `FileCore`. Nothing else — **no `SwiftUI` import** (matching `OutlineUI`, whose `@Observable` controller imports only `Observation`), and **no `AppKit`**: file-type icons are `NSWorkspace.shared.icon(forFile:)` and therefore a view concern.

### 4.2 Public API contract — value types (`Sendable` + `Equatable` throughout)

```swift
// FileTree/DirectoryEntry.swift

/// One filesystem entry as read from disk. The IO edge produces these;
/// every function downstream is pure.
public struct DirectoryEntry: Sendable, Equatable, Identifiable, Hashable {
    /// ALWAYS `standardizedFileURL`, ALWAYS built with the correct
    /// `isDirectory` flag (D4). Normalization happens in `init` and nowhere
    /// else. Symlinks are NOT resolved.
    public let url: URL
    public var id: URL { url }

    public let name: String            // url.lastPathComponent
    public let isDirectory: Bool
    public let isHidden: Bool
    public let isPackage: Bool         // .app/.rtfd — rendered as a leaf, never expanded
    public let isSymbolicLink: Bool

    public init(url: URL, isDirectory: Bool, isHidden: Bool, isPackage: Bool, isSymbolicLink: Bool)
}

// FileTree/FileTreeFilter.swift

public struct FileTreeFilter: Sendable, Equatable, Codable {
    public var showsHiddenFiles: Bool      // default false
    public var supportedFilesOnly: Bool    // default false (§2.5, §10.1)
    public var foldersFirst: Bool          // default true
}

public enum FileTreeArrangement {
    /// Filter, then sort. Pure. O(n log n).
    ///
    /// - `supportedFilesOnly` NEVER removes a directory: you cannot navigate to
    ///   a supported file inside a folder the filter deleted.
    /// - Names sort with `localizedStandardCompare` (Finder order: "f2" before
    ///   "f10"), case-insensitively. See §4.7 for the 10k perf note — this
    ///   comparator is the single hottest thing in the epic.
    /// - `foldersFirst` partitions before the name sort; when false, folders and
    ///   files interleave by name.
    public static func arrange(
        _ entries: [DirectoryEntry],
        filter: FileTreeFilter,
        supportedExtensions: Set<String>
    ) -> [DirectoryEntry]
}

// FileTree/FileTreeDiff.swift

public struct DirectoryDiff: Sendable, Equatable {
    public let added: [DirectoryEntry]
    public let removed: [DirectoryEntry]
    /// Same URL, changed attributes (e.g. a file became a directory, or a
    /// package flag flipped). Rare, but it is the case that silently renders a
    /// stale chevron if the diff ignores it.
    public let changed: [DirectoryEntry]
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
}

public enum FileTreeDiff {
    /// Set difference on `url`, then attribute comparison on the intersection.
    /// A rename is `removed` + `added`; no rename detection is attempted (D4).
    public static func diff(old: [DirectoryEntry], new: [DirectoryEntry]) -> DirectoryDiff
}

// FileTree/FileTreeRow.swift

/// One rendered row. `depth` is tree position; the view indents by it.
public struct FileTreeRow: Sendable, Equatable, Identifiable {
    public let entry: DirectoryEntry
    public let depth: Int
    public let isExpanded: Bool
    public let isLoading: Bool          // spinner on the row, not a whole-tree state
    public var id: URL { entry.url }
}

// FileTree/FolderAvailability.swift

public enum FolderAvailability: Sendable, Equatable {
    case noRoot
    case loading
    case rootUnreadable(reason: String)
    case empty
    case emptyAfterFilter
    case ready
}

// FileTree/FileTreeOperations.swift

public enum FileTreeOperationError: Error, Sendable, Equatable {
    case nameEmpty
    case nameContainsPathSeparator
    case nameExists(String)
    case sourceMissing
    case destinationNotDirectory
    case moveIntoOwnSubtree
    case underlying(String)             // stringified so the error stays Equatable
}

public enum FileTreeNaming {
    /// Finder uniquing: "untitled.md" → "untitled 2.md" → "untitled 3.md".
    public static func uniqueName(base: String, extension ext: String, existing: Set<String>) -> String
    /// Finder duplicate: "notes.md" → "notes copy.md" → "notes copy 2.md".
    public static func duplicateName(of name: String, existing: Set<String>) -> String
    /// Case-INSENSITIVE collision check (APFS), with `currentName` excluded so a
    /// case-only rename is legal (D10).
    public static func validate(_ name: String, existing: Set<String>, currentName: String?) -> FileTreeOperationError?
}

public enum FileTreeMoveValidation {
    /// Path-COMPONENT containment, not string prefix (D10).
    public static func validate(source: URL, intoDirectory destination: URL) -> FileTreeOperationError?
}
```

### 4.3 Public API contract — IO seams

```swift
// FileTree/DirectoryReading.swift

public protocol DirectoryReading: Sendable {
    /// Lists `url`'s immediate children. Throws for missing/unreadable/not-a-directory.
    func contents(of url: URL) throws -> [DirectoryEntry]
}

/// The real reader. MUST use the batched form:
///     contentsOfDirectory(at:includingPropertiesForKeys:options:)
/// with [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey].
/// Fetching those keys per-URL afterwards is 4 × 10 000 extra stat calls and
/// is the difference between meeting and missing the 200 ms budget (§4.7).
public struct FileSystemDirectoryReader: DirectoryReading { public init() }

// FileTree/FileSystemMutating.swift

public protocol FileSystemMutating: Sendable {
    func createFile(at url: URL) throws
    func createDirectory(at url: URL) throws
    func move(from source: URL, to destination: URL) throws
    func copy(from source: URL, to destination: URL) throws
    /// `FileManager.trashItem` — never `removeItem` (D10).
    func trash(at url: URL) throws
}

public struct FileSystemMutator: FileSystemMutating { public init() }

// FileTree/DirectoryWatcher.swift

/// One `DispatchSource` over one directory fd.
///
/// NOT `@MainActor` (D5): a nonisolated `deinit` cannot call a main-actor
/// isolated method, so `deinit { cancel() }` — the whole point — only compiles
/// on a non-isolated type. `onChange` is invoked on `queue`; the callee hops to
/// the main actor.
public final class DirectoryWatcher: @unchecked Sendable {
    /// `@unchecked` because `DispatchSourceFileSystemObject` carries no
    /// `Sendable` conformance while being documented as thread-safe; the fd is
    /// owned solely by the cancel handler and is never read elsewhere.
    public init(url: URL, queue: DispatchQueue, onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void) throws
    public func cancel()          // idempotent
    deinit                        // cancels
}

public enum DirectoryWatchEvent: Sendable, Equatable {
    case contentsChanged          // .write — re-list and diff
    case vanished                 // .delete / .rename / .revoke on the watched dir itself
}

public protocol DirectoryWatching: Sendable {
    func watch(_ url: URL, onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void) throws -> DirectoryWatcherHandle
}
```

`DirectoryWatching` exists so `FileTreeModel` tests can inject a fake that records watched URLs and fires events **synchronously on demand** — no `Task.sleep`-and-hope. The real `DispatchSource` gets its own small integration test against a temp directory, using a bounded polling helper (house rule; `MarkdownEngineTests/Fixtures.wait` is the shape to copy).

### 4.4 Public API contract — the model

```swift
// FileTree/FileTreeModel.swift

/// Per-window folder-browser state (root is per window, #28). Main-actor
/// isolated: written from SwiftUI handlers and watcher hops, read from bodies.
@MainActor
@Observable
public final class FileTreeModel {
    public private(set) var root: URL?
    public private(set) var availability: FolderAvailability
    /// Flattened, depth-annotated, filter-applied. STORED (D15) — recomputed on
    /// structural change only, never per body evaluation.
    public private(set) var rows: [FileTreeRow]

    /// The user's selected node. Projected into `SidebarSelection` by the app (D8).
    public var selectedURL: URL?

    /// Non-nil while a row is in inline-rename mode. Consume-and-clear, same
    /// contract as `OutlineController.pendingJumpLineRange`.
    public var renamingURL: URL?

    /// Set by `open(_:)`; the app consumes it, opens a tab, and clears it.
    public var pendingOpenURL: URL?

    /// Instrumentation for the "no fd leaks" acceptance box (D5). Equals the
    /// number of live `DispatchSource`s: root + expanded directories.
    public var watchedDirectoryCount: Int { get }

    public init(
        reader: any DirectoryReading = FileSystemDirectoryReader(),
        mutator: any FileSystemMutating = FileSystemMutator(),
        watcher: any DirectoryWatching = FileSystemDirectoryWatching(),
        preferences: FileTreePreferences,
        supportedExtensions: Set<String>
    )

    // MARK: Root & structure
    public func setRoot(_ url: URL?) async
    public func expand(_ url: URL) async
    public func collapse(_ url: URL)          // keeps children cache, drops watcher (D3)
    public func toggleExpansion(_ url: URL) async
    /// `windowDidBecomeKey` (D6). Re-lists every expanded directory and applies
    /// diffs. A no-op diff produces no `rows` assignment and therefore no render.
    public func rescanExpandedDirectories() async
    /// Cancels every watcher. Idempotent; called from `windowWillClose`.
    public func tearDown()

    // MARK: Reveal
    /// Expands every ancestor from the root down and selects `url` (§4.8).
    /// Returns `false` when `url` is outside the current root or missing —
    /// the caller decides whether to offer "open its enclosing folder".
    @discardableResult
    public func reveal(_ url: URL) async -> Bool

    // MARK: CRUD — each validates purely, then performs exactly one syscall
    public func createFile(in directory: URL) async throws(FileTreeOperationError) -> URL
    public func createFolder(in directory: URL) async throws(FileTreeOperationError) -> URL
    public func rename(_ url: URL, to newName: String) async throws(FileTreeOperationError) -> URL
    public func duplicate(_ url: URL) async throws(FileTreeOperationError) -> URL
    public func move(_ url: URL, intoDirectory destination: URL) async throws(FileTreeOperationError) -> URL
    /// Caller shows the confirm alert first; this performs the trash.
    public func moveToTrash(_ url: URL) async throws(FileTreeOperationError)

    /// Re-keys `expanded`, `children` and `watchers` for a moved node and all
    /// cached descendants (D10). Called by the mutating methods above; exposed
    /// so a caller that moves a file by other means can keep the tree honest.
    public func itemWasRenamed(from old: URL, to new: URL)
}
```

**Threading:** the class is `@MainActor`. The `async` methods `await` the reader off the main actor (a detached listing) and apply results back on it. The watcher's `onChange` runs on its own queue and hops in via `Task { @MainActor in … }`. **No actor is introduced.** If the implementation reaches for one, that is a design error — the state is SwiftUI-observed and belongs on the main actor.

### 4.5 App-wide preferences and recents

```swift
// FileTree/FileTreePreferences.swift

/// ONE instance per process, created by `AppDelegate`, injected into every
/// window (D7). No per-window cached copy exists, so #34's staleness cannot
/// occur for this state.
@MainActor
@Observable
public final class FileTreePreferences {
    public var filter: FileTreeFilter          // write-through on didSet
    public var opensOnSingleClick: Bool        // default false (§10.3)
    public init(store: any FileTreePreferenceStoring = UserDefaultsFileTreePreferenceStore())
}

@MainActor
public protocol FileTreePreferenceStoring {
    var filter: FileTreeFilter { get set }
    var opensOnSingleClick: Bool { get set }
    var recentRootBookmarks: [Data] { get set }
}

// FileTree/RecentFolderRoots.swift

/// App-wide, most-recent-first, deduped by resolved URL, capped at 10.
/// Entries are `bookmarkData(options: .withSecurityScope)` — which works
/// unsandboxed and makes sandboxing an entitlement change only (D14).
@MainActor
@Observable
public final class RecentFolderRoots {
    public private(set) var roots: [URL]
    public func record(_ url: URL)
    /// Resolution failures (folder deleted) drop that entry and return nil.
    /// Stale-but-resolvable bookmarks resolve to the folder's new location and
    /// are re-saved in place.
    public func resolve(_ url: URL) -> URL?
    public func clear()
}
```

### 4.6 `Workspace` / `FileCore` additions contract (exact)

```swift
// FileCore/FileDocument.swift  (D12)
public private(set) var id: String
public private(set) var format: FileFormat
public func renamed(to url: URL) -> FileDocument

// Workspace/WorkspaceModel.swift
/// Sets the folder root without a panel (recents, reveal, session restore).
/// `openFolder()` becomes a thin wrapper: panel → setFolderRoot.
public func setFolderRoot(_ url: URL?)

// Workspace/TabStore.swift  — pure, synchronous, testable (D11)
public enum DeletedDocumentOutcome: Sendable, Equatable {
    case notOpen
    case closedCleanTab(UUID)
    case needsPrompt(UUID)          // the tab was dirty
}
public func tabID(forFileURL url: URL) -> UUID?      // standardized comparison
public func documentWasRenamed(from old: URL, to new: URL)
public func documentFileWasDeleted(at url: URL) -> DeletedDocumentOutcome

// Workspace/WorkspaceSession.swift  (D13)
public var folderRootBookmark: Data?    // NEW, optional → NO version bump
```

### 4.7 Performance: where the 200 ms goes

The budget is *"Folder with 10 000 entries → expand < 200 ms"*. Three costs, in the order they will bite:

1. **`localizedStandardCompare` — the likely failure point.** 10 000 entries is ~130 000 comparisons, and `localizedStandardCompare` is an ICU call, not a memcmp. This is the one number in the epic that plausibly blows the budget on its own. **Measure it first, in isolation, before building anything on top of it.** If it does not fit: precompute a sort key per entry once (`name.lowercased()` plus a digit-run-aware transform) and sort on that, keeping `localizedStandardCompare` only as the tie-break. Do not silently swap to `<` — "f10" before "f2" is a visible regression against Finder.
2. **The listing itself.** `contentsOfDirectory(at:includingPropertiesForKeys:options:)` with all four keys prefetched. The naive version — list URLs, then call `resourceValues` per URL — is 40 000 extra stats and will miss the budget by itself.
3. **The flatten.** Guarded by D15 (stored, not per-body). `List`/`ForEach` rendering is lazy in the AppKit backend and is not part of this budget.

The perf test measures **expand of a real 10 000-file temp directory**, end to end (list → arrange → flatten), because that is what the budget says. A synthetic `arrange`-only benchmark is useful for bisecting cost 1 but does not replace it.

### 4.8 App-target integration (exact wiring)

**`AppDelegate.swift`** — create `FileTreePreferences` and `RecentFolderRoots` once; pass both into `WindowCoordinator`.

**`WindowCoordinator.swift`**
- Hold the shared `preferences` / `recentRoots`; pass to each `WindowController`.
- `func openFolder(_ url: URL)` — `keyModel?.setFolderRoot(url)`, `recentRoots.record(url)`, `scheduleSaveSession()`.
- `func revealActiveFile()` — key controller → `fileTreeModel.reveal(activeDocument.fileURL)`; on `false`, offer to open the file's enclosing directory as the root.
- `func documentWasRenamed(from:to:)` / `func documentFileWasDeleted(at:)` — walk `controllers`, use the `TabStore` intents (§4.6), present the delete alert (D11). Called **only** from the sidebar's CRUD completion handlers.
- `saveSession()` — include the key window's `folderRootBookmark` in each `TabRecord`.

**`WindowController.swift`**
- `let fileTreeModel: FileTreeModel`, constructed alongside `outlineController`, with the injected shared preferences.
- Pass to `WorkspaceShellView` → `SidebarView`.
- `windowWillClose` → `fileTreeModel.tearDown()` in the same block as `parseStore.evictAll()`.
- `windowDidBecomeKey` → `Task { await fileTreeModel.rescanExpandedDirectories() }` (D6).

**`SidebarView.swift`** — the bulk of the app work:
- `List(selection:)` rebinds to `Binding<SidebarSelection?>` (D8); existing outline rows change `.tag(row.item.id)` → `.tag(SidebarSelection.outline(row.item.id))`.
- `folderContent` switches on `fileTreeModel.availability` (D9); `.ready` renders `ForEach(fileTreeModel.rows)`.
- `FileTreeRowView`: chevron for directories (from `isDirectory`, never from a child count), `NSWorkspace.shared.icon(forFile:)`, name, `.padding(.leading, depth * 14)`, `.frame(maxWidth: .infinity)` + `.contentShape(Rectangle())` + `.simultaneousGesture(TapGesture())` — **copy E08's gesture treatment verbatim**; its comments record why a plain `.onTapGesture` inside a `List` row intermittently does nothing.
- Inline rename: a `TextField` swapped in when `fileTreeModel.renamingURL == entry.url`; Return commits, Escape cancels, focus-loss commits.
- `.contextMenu`: New File, New Folder, Rename, Duplicate, Reveal in Finder, Move to Trash.
- `.draggable(entry.url)` + `.dropDestination(for: URL.self)` on directory rows and on the root header; dropping onto a *file* row targets its parent directory.
- Filter menu in the section header: Show Hidden Files, Supported Files Only, Folders First — bound straight to `preferences.filter`.
- `.onKeyPress(.return)` switches on the selection case (D8).
- Accessibility identifiers for the UI test: `folderSection`, `fileRow-<lastPathComponent>`, `newFileButton`.

**`WorkspaceCommands.swift`**
- `Menu("Open Recent Folder")` under Open Folder…, from `recentRoots.roots`, plus "Clear Menu".
- `Button("Reveal Active File")` — **⇧⌘J**, Xcode's "Reveal in Project Navigator" binding (§10.2), disabled without an active file-backed document.
- New File / New Folder in the folder root, disabled without a root.

**`WorkspaceShellView.swift`** — accept and pass through `fileTreeModel` (mirrors how `outlineController` threads through today).

### 4.9 Failure matrix (graceful totality)

| Input | Outcome |
|---|---|
| No folder opened | `.noRoot`; "No folder opened" + ⌘⇧O hint |
| Root deleted while open | watcher `.vanished` → `.rootUnreadable`; watchers cancelled; no crash |
| Root is a file, not a directory | `.rootUnreadable(reason:)` at `setRoot` |
| Directory unreadable (`EACCES`) | that row's load state is `.failed`; the row renders with a warning affordance; the rest of the tree is unaffected |
| Filters hide every entry | `.emptyAfterFilter` (D9) — never `.empty` |
| `supportedFilesOnly` on, folder of directories | directories always survive the filter (§4.2) |
| Extensionless file (`README`, `Makefile`) + `supportedFilesOnly` | hidden — the registry defines "supported" and returns nil for empty extensions (§2.5, §10.1) |
| Package directory (`.app`, `.rtfd`) | leaf row, no chevron, not expandable |
| Symlinked directory | expandable; the URL is standardized but **not** resolved, so children stay under the link's path (D4) |
| Watcher fires, listing unchanged (our own atomic save) | diff is empty → no `rows` assignment → no render (D6) |
| Expanded directory removed externally | diff `removed` → watcher cancelled, subtree cache evicted, rows rebuilt |
| Collapse then re-expand | instant from cache; correctness restored by the parent's watcher and the focus rescan (D3) |
| Rename `notes.md` → `Notes.md` (case only) | allowed — collision check excludes the item's own name (D10) |
| Rename to an existing sibling's name | `.nameExists`; no syscall attempted |
| Name containing `/` or `:` | `.nameContainsPathSeparator`; no syscall attempted |
| Drag a folder into its own descendant | `.moveIntoOwnSubtree`, decided by path components (`/a/foo` is not inside `/a/foobar`) |
| Drag onto the directory it is already in | no-op, not an error |
| Drop from Finder onto a file row | targets that file's **parent** directory |
| Rename an expanded folder | expansion, cache and watchers re-key to the new path; the folder stays open (D10) |
| Rename an **open** file | `FileDocument.renamed(to:)`; title (≤250 ms poll), save target, `format`, highlighter and preview routing all follow (D12) |
| Rename an open `.md` → `.txt` | format changes → highlighter re-attaches, preview routes to `NoPreviewView`, outline goes `.unsupportedFormat` — all existing machinery, now reachable |
| Delete an open **clean** document | its window closes; no alert (D11) |
| Delete an open **dirty** document | one alert: Save As… / Close Without Saving / Keep Open; "Keep Open" leaves ⌘S able to recreate the file |
| External delete/rename of an open document | tree updates; **the document does not react — E18** (§2.6) |
| Reveal a file outside the current root | `reveal` returns `false`; the command offers to open its enclosing folder |
| Reveal with no root open | same path as above |
| Recent root no longer exists | bookmark resolution fails → entry dropped from the list, nothing opens, no alert |
| Recent root was moved | bookmark resolves stale → root opens at the new location, bookmark re-saved (D14) |
| `session.json` written before this epic | `folderRootBookmark` decodes as `nil`, tabs restore normally — no version bump (D13) |
| 10 000-entry directory expanded | < 200 ms, measured end to end (§4.7) |
| Window closed with 30 directories expanded | `tearDown()` → `watchedDirectoryCount == 0` (D5) |

---

## 5. File layout (exact)

```
MacDown2/Packages/MacDownKit/Sources/FileTree/
  FileTree.swift               (keep the module enum)
  DirectoryEntry.swift         (NEW — the only URL-normalization site, D4)
  DirectoryReading.swift       (NEW — protocol + FileSystemDirectoryReader)
  DirectoryWatcher.swift       (NEW — DispatchSource, non-MainActor, D5)
  FileSystemMutating.swift     (NEW — protocol + FileSystemMutator)
  FileTreeFilter.swift         (NEW — FileTreeFilter + FileTreeArrangement)
  FileTreeDiff.swift           (NEW — pure diff)
  FileTreeRow.swift            (NEW)
  FileTreeNaming.swift         (NEW — unique/duplicate/validate, pure)
  FileTreeOperations.swift     (NEW — FileTreeOperationError + move validation)
  FolderAvailability.swift     (NEW)
  FileTreeModel.swift          (NEW — the per-window model)
  FileTreePreferences.swift    (NEW — app-wide shared observable + store, D7)
  RecentFolderRoots.swift      (NEW — bookmark-backed recents)
  FolderAccessScope.swift      (NEW — balanced security-scoped access, D14)

MacDown2/Packages/MacDownKit/Sources/FileCore/
  FileDocument.swift           (id/format relax; + renamed(to:), D12)

MacDown2/Packages/MacDownKit/Sources/Workspace/
  WorkspaceModel.swift         (+ setFolderRoot)
  TabStore.swift               (+ tabID(forFileURL:), documentWasRenamed, documentFileWasDeleted)
  WorkspaceSession.swift       (+ TabRecord.folderRootBookmark)

MacDown2/Packages/MacDownKit/Tests/
  FileTreeTests/Fixtures.swift                 (NEW — entry builders, fake reader/
                                                mutator/watcher, bounded `wait`)
  FileTreeTests/DirectoryEntryTests.swift      (NEW — normalization, symlinks)
  FileTreeTests/FileTreeArrangementTests.swift (NEW — sort/filter)
  FileTreeTests/FileTreeDiffTests.swift        (NEW)
  FileTreeTests/FileTreeNamingTests.swift      (NEW)
  FileTreeTests/FileTreeOperationsTests.swift  (NEW — validation, pure)
  FileTreeTests/FileTreeCRUDTests.swift        (NEW — real mutator, temp dirs)
  FileTreeTests/FileTreeModelTests.swift       (NEW — fakes: expand/collapse/diff/reveal/re-key)
  FileTreeTests/DirectoryWatcherTests.swift    (NEW — real DispatchSource, bounded poll, fd count)
  FileTreeTests/FileTreePreferencesTests.swift (NEW — shared-instance behaviour, D7)
  FileTreeTests/RecentFolderRootsTests.swift   (NEW — bookmarks, dedupe, cap)
  FileTreeTests/FolderAccessScopeTests.swift   (NEW — balanced start/stop, D14)
  FileTreeTests/FileTreePerformanceTests.swift (NEW — 10k expand < 200 ms)
  FileTreeTests/FileTreeTests.swift            (existing stub — keep or fold in)
  FileCoreTests/FileDocumentTests.swift        (extend: renamed(to:) — id, format, text/state preserved)
  WorkspaceTests/TabStoreFileURLTests.swift    (NEW — tabID/rename/delete intents)
  WorkspaceTests/WorkspaceSessionStoreTests.swift (extend: pre-epic JSON still decodes)
  WorkspaceTests/WorkspaceModelTests.swift     (extend: setFolderRoot)

MacDown2/MacDown2/
  SidebarSelection.swift       (NEW — D8)
  SidebarView.swift            (folder section, rows, rename, drag/drop, filter menu)
  WindowController.swift       (+ fileTreeModel, teardown, focus rescan)
  WindowCoordinator.swift      (+ shared prefs/recents, openFolder(url:), reveal,
                                rename/delete intents, root in session)
  WorkspaceShellView.swift     (+ pass-through)
  WorkspaceCommands.swift      (+ Open Recent Folder, Reveal Active File ⇧⌘J, New File/Folder)
  AppDelegate.swift            (+ construct the shared preferences/recents)
MacDown2/MacDown2UITests/FolderBrowserUITests.swift  (NEW — build-for-testing in CI)

planning/epic-09-implementation.md   (this file)
README.md                            (status + module map: FileTree no longer a stub)
```

## 6. Build-config changes (exact)

**None.** `FileTree` is already a product in `Package.swift` with `dependencies: ["FileCore"]`, already has a `FileTreeTests` target, and is already listed under the `MacDown2` app target in `project.yml`. The new UI test file joins the existing `MacDown2UITests` target. `ci.yml` needs no change — `swift test` and `build-for-testing` already cover everything added here.

If a `Package.swift`, `project.yml`, or `ci.yml` diff appears in this PR, something has gone wrong.

## 7. Test plan (mapped to issue #10 acceptance + deliverables)

| # | Issue box / deliverable | Test (CI = `swift test` unless noted) |
|---|---|---|
| 1 | External `touch new.md` in an expanded folder appears < 1 s | `DirectoryWatcherTests.realWatcherReportsExternalCreate`: real `DispatchSource` on a temp dir, `touch` a file, bounded poll (house-rule helper, never a fixed sleep) asserts the change is observed well inside 1 s. Plus `FileTreeModelTests.watchEventTriggersRelistAndDiff` with the **fake** watcher, which fires synchronously and asserts the resulting `rows` |
| 2 | Deleting the file open in the active tab offers close/discard; no crash | `TabStoreFileURLTests`: clean tab → `.closedCleanTab(id)`; dirty tab → `.needsPrompt(id)`; URL not open → `.notOpen`; a URL differing only by `.standardizedFileURL` normalization still matches. `FolderBrowserUITests` (local) drives the alert |
| 3 | Renaming an open file updates tab title + save target | `FileDocumentTests.renamedUpdatesURLIDAndFormat`: `notes.md` → `notes.txt` changes `fileURL`, `id`, **and** `format` while preserving `text`, `state`, `lastKnownModificationDate`. `TabStoreFileURLTests.documentWasRenamedRepointsTheTab`. `FolderBrowserUITests` (local) asserts the window title after the 250 ms poll |
| 4 | Watching scoped to expanded folders (no fd leaks, instrumented) | `FileTreeModelTests`: after `setRoot` → `watchedDirectoryCount == 1`; expand two → `3`; collapse one → `2`; `tearDown()` → `0`. `watchChurnStaysBounded`: 200 expand/collapse cycles, count never exceeds expanded+1 and ends at 0. `DirectoryWatcherTests.cancelIsIdempotent` (double-cancel must not double-close) |
| 5 | Filter toggle hides non-registered extensions immediately | `FileTreeArrangementTests`: `supportedFilesOnly` keeps `.md`/`.json`/`.py`, drops `.png`/`.o`, **keeps every directory**, drops extensionless files (§2.5 — pin the decision so a later change is a deliberate one). `FileTreeModelTests.filterChangeRebuildsRowsWithoutRelisting` — no `DirectoryReading` call on a filter flip |
| D2 | Tree diffing on FS events | `FileTreeDiffTests`: add-only, remove-only, both, attribute-changed, identical → `isEmpty`, empty↔populated, ordering-independence. `FileTreeModelTests.emptyDiffDoesNotReassignRows` — the render-suppression property D6 rests on |
| D2 | Sort / filter | `FileTreeArrangementTests`: `localizedStandardCompare` ordering (`f2` before `f10`, pinned explicitly); case-insensitive name order; `foldersFirst` on/off; hidden files on/off; dotfiles; combined filters; empty input |
| D2 | CRUD against temp dirs | `FileTreeCRUDTests` with the **real** mutator: create file/folder with uniquing; rename; rename case-only (`notes.md` → `Notes.md`) succeeds on APFS; duplicate produces `notes copy.md` then `notes copy 2.md`; move; move into own subtree rejected **before** any syscall; trash puts the item in the Trash and not in the void; collision rejected; every failure leaves the directory byte-identical |
| D3 | Perf: 10k-entry folder expand < 200 ms | `FileTreePerformanceTests.expandTenThousandEntries`: build the temp dir once, measure list→arrange→flatten (§4.7). Record the measured number in the PR — the comparator is the thing most likely to blow the budget |
| D4 | XCUITest: create file in sidebar → opens in tab | `FolderBrowserUITests` (local; `build-for-testing` in CI): launch with a folder root, New File in the sidebar, assert a new tab exists with the new name, then rename it in the sidebar and assert the tab title follows |
| — | Node identity / normalization (D4) | `DirectoryEntryTests`: trailing-slash directory URLs normalize to one key; `.`/`..` collapse; a symlinked directory keeps the **link's** path, not the target's |
| — | Reveal (§4.8) | `FileTreeModelTests`: reveal a deeply nested file expands every ancestor and selects it; reveal outside the root returns `false` and changes nothing; reveal with no root returns `false` |
| — | Rename re-keys tree state (D10) | `FileTreeModelTests.renamingAnExpandedFolderKeepsItExpanded`: expand `a/b/c`, rename `a/b` → `a/z`, assert `expanded`, the children cache, and the watcher set all moved to `a/z`, and that `watchedDirectoryCount` is unchanged |
| — | Availability totality (D9) | `FileTreeModelTests`: no root → `.noRoot`; unreadable root → `.rootUnreadable`; genuinely empty → `.empty`; all-filtered → `.emptyAfterFilter`; populated → `.ready`. All five asserted, none inferred |
| — | Preferences are app-wide (D7) | `FileTreePreferencesTests`: two `FileTreeModel`s sharing one `FileTreePreferences` both see a filter change (the #34 shape, pinned so it cannot regress into per-window caches) |
| — | Recents + security-scoped access (D14) | `RecentFolderRootsTests`: most-recent-first, dedupe, cap at 10, unresolvable bookmark drops silently, moved folder resolves via the bookmark and is re-saved. `FolderAccessScopeTests`: a scoped-bookmark round trip over a temp dir starts and stops exactly once, and a scope over a plain (un-bookmarked) URL reports not-started and does **not** call stop |
| — | Session compatibility (D13) | `WorkspaceSessionStoreTests`: a `session.json` written **without** `folderRootBookmark` still decodes with `version == 1` and full tabs |

House rules carried from E05–E08: `@Test`/`#expect` only; **no `Task.sleep`-and-hope** — await deterministic signals, or use a bounded polling helper for the one genuinely asynchronous seam (the real watcher); no real `UserDefaults` (in-memory suite); no fixture files checked into the repo — build temp trees in the test.

## 8. Implementation order (suite green at every step)

1. **D12 — `FileCore.FileDocument.renamed(to:)`** plus the `id`/`format` relaxation. Own commit, own tests. It is a `FileCore` change and review should see it separately from the folder browser.
2. `DirectoryEntry` + `DirectoryReading` + `FileSystemDirectoryReader` → normalization tests, real-temp-dir reader test.
3. `FileTreeFilter` + `FileTreeArrangement` → sort/filter tests. **Run the 10k comparator microbenchmark here** (§4.7) before anything is built on top of it.
4. `FileTreeDiff` → diff tests.
5. `FileTreeNaming` + `FileTreeOperations` validation → pure tests (no disk).
6. `FileSystemMutating` + `FileSystemMutator` → CRUD-against-temp-dir tests.
7. `DirectoryWatcher` + `DirectoryWatching` + the fake → real-watcher integration test, cancel/idempotence, fd-count instrumentation. **Push and check CI after this step** — it is the concurrency-heavy one (§9).
8. `FolderAvailability` + `FileTreeModel` → model tests with fakes (expand/collapse, load states, diff application, re-key on rename, reveal, availability totality, watch scope).
9. `FileTreePreferences` + store, `RecentFolderRoots`, `FolderAccessScope`.
10. `Workspace`: `setFolderRoot`, the three `TabStore` intents, `TabRecord.folderRootBookmark` (+ the pre-epic-JSON decode test).
11. App wiring: `AppDelegate` shared objects, `WindowController` ownership/teardown/focus-rescan, `WorkspaceShellView` pass-through.
12. `SidebarSelection` + `SidebarView` (D8 first, as its own commit — it touches E08's rows and should be reviewable without folder code mixed in), then the folder section, rows, context menu, inline rename, drag/drop, filter menu.
13. `WorkspaceCommands`: Open Recent Folder, Reveal Active File ⇧⌘J, New File/Folder.
14. `FileTreePerformanceTests` (10k); `FolderBrowserUITests`; local run.
15. README status + module map (`FileTree` no longer a stub).

## 9. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test
cd ../.. && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build-for-testing
swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
# Locally on macOS 26 (UI test — record the result on the PR):
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' test -only-testing:MacDown2UITests/FolderBrowserUITests
```

**Push and read CI before declaring the watcher work verified.** CI runs Xcode 26.0.1, which rejected concurrency code the newer local toolchain accepted during E07. This epic adds a `DispatchSource`, a `@Sendable` escaping callback, an `@unchecked Sendable` class, and a background→main-actor hop — the largest concurrency surface since E07. "Builds locally" is not evidence here. Push after step 7 and again at the end.

Also record on the PR: the **measured 10k expand time** (§4.7) and the **`watchedDirectoryCount` behaviour** from the churn test — those are the two acceptance boxes whose numbers a reviewer cannot re-derive from the diff.

### Implementation evidence

Epic 9 is implemented and merged. The Release `tenThousandEntryListingArrangementAndFlatteningBenchmark` measured **115.79 ms**, below the 200 ms budget. The watcher acceptance sequence is **1** directory after `setRoot`, **3** after expanding two folders, **2** after collapsing one, and **0** after `tearDown()`; the churn test keeps the count bounded by expanded directories plus the root. The implementation preserves the plan's decisions: supported-file filtering is off by default, double-click opens while single-click selects, Finder drops copy, internal drags move, collisions reject, and roots remain per-window while preferences and recents are shared.

## 10. Implementation decisions (recorded for review)

1. **"Supported files only" hides extensionless files** (§2.5). `README`, `LICENSE`, `Makefile`, `Dockerfile` have no path extension, so `FileFormat.format(for:in:)` returns `nil` and the filter hides them. The plan treats the registry as the definition of "supported" and ships the filter **off by default**, so it is always a deliberate act. The alternative — a special case that keeps extensionless files — makes the filter's rule un-nameable.
2. **⇧⌘J for Reveal Active File.** Free in the current command table (taken: ⌘N/⌘T/⌘O/⌘⇧O/⌘S/⌘⇧S/⌘W/⌘1–9/⌥⌘1–3/⌃⌘S/⌃⌘O/⌃Tab/⌃⇧Tab). Chosen for Xcode's "Reveal in Project Navigator" precedent.
3. **Single- vs double-click to open.** The epic says "single/double per pref". The implementation defaults to **double-click opens, single-click selects**, because under native tabs every open creates a window, and single-click-opens would spawn one per arrow-key-adjacent click. The pref exists and flips it. (VS Code single-clicks because it has a reusable preview tab; we do not.)
4. **Drops from Finder copy; drags within the tree move.** Finder itself moves within a volume and copies across; matching that exactly means reading volume identifiers on every drag. The implementation takes the simpler, more predictable rule and states it in the drop feedback.
5. **Name collision on move/drop is rejected, not merged or auto-renamed.** Finder asks (Replace / Keep Both / Stop). A three-way sheet is real UI work for a case that is rare in a Markdown editor's sidebar. Plan: reject with the reason. Flag if Keep Both is wanted for v1.
6. **No cap on the number of watched directories.** Watch scope is already bounded by "expanded", which is bounded by the user's patience; the process fd budget is far above any plausible number of hand-expanded folders. A cap plus LRU eviction was considered and rejected as speculative — the instrumented count (D5) is what would reveal it becoming a problem. The implementation retains this bounded-by-expansion model.
7. **`.emptyAfterFilter` offers a "Clear filters" button** (D9) that resets `preferences.filter` to defaults — app-wide, so it affects every window. Alternative is a passive message. Plan takes the button.
8. **The folder root stays per window** (#28), while filters and recents are app-wide (D7). Opening a folder in window A does not change window B. This is the amendment's reading, but it produces a mixed model, so it is worth an explicit yes.
9. **This epic does not fix #34.** D7 keeps *new* preference state out of the stale-cache pattern by using a single shared observable, which is one of the two fixes #34 proposes — but it deliberately does not retrofit `sectionOrder`/`sectionExpanded`, because #34 says the app-wide-vs-per-window product question has to be answered first. The implementation preserves that split.
10. **`FileDocument.saveAs(_:)` keeps its stale `id`** (D12). It has the same problem `renamed(to:)` fixes, but changing it moves the `RecoveryBuffer` key for untitled documents mid-session, which is a session-restore concern that deserves its own change rather than a ride-along. Flagged, not fixed.
11. **Delete of an open clean document closes its window with no alert** (D11). Acceptance says "offers close/discard flow"; for a clean document there is nothing to discard and the alert would be OK-only. The implementation uses the no-alert clean-document path.

## 11. Hand-off notes / known pitfalls (condensed — mirrored to the PR inline comment)

- **Normalize URLs in exactly one place** (`DirectoryEntry.init`) and **never resolve symlinks** (D4). `file:///a/b` and `file:///a/b/` are different `Hashable` keys, and a directory keyed both ways can be expanded and collapsed simultaneously. `standardizedFileURL` yes; `resolvingSymlinksInPath` no — it moves a symlinked folder's children under the target and breaks the parent→child relation the tree is built from.
- **`close(fd)` goes in the `DispatchSource` cancel handler and nowhere else** (D5). Closing before cancellation completes is a use-after-close on a descriptor number the process can immediately reuse.
- **`DirectoryWatcher` must not be `@MainActor`** (D5). A nonisolated `deinit` *can* read isolated stored properties (this was verified — don't repeat the folklore that it can't), but it **cannot call an isolated method**, so the moment you factor cancellation into a `cancel()` helper on a main-actor type, `deinit { cancel() }` stops compiling and the workaround (`Task { @MainActor in … }`) resurrects `self` and never runs. Keep the fd-owning type non-isolated.
- **A filesystem event carries no payload: re-list, diff, apply** (D6). And the diff is not an optimization — MacDown's own atomic save fires the watcher several times per save on a directory whose listing never changed. Without the diff, typing re-renders the tree.
- **Re-list off the main actor.** A 10 000-entry `contentsOfDirectory` on the main actor drops frames. Hop back to apply.
- **Use the batched `contentsOfDirectory(at:includingPropertiesForKeys:options:)`** with all four resource keys (§4.3). Per-URL `resourceValues` afterwards is 40 000 extra stats on a 10k folder and misses the budget on its own.
- **Measure `localizedStandardCompare` on 10 000 names before building on it** (§4.7). It is the single most likely reason the 200 ms budget fails, and the wrong fix (plain `<`) is a visible Finder-order regression.
- **`rows` is stored, not computed** (D15). E08 computes `visibleRows` in `body`; that is fine for an outline and quadratic for a folder.
- **Compare sibling names case-insensitively and exclude the item's own name** (D10). APFS is case-insensitive by default, and `notes.md` → `Notes.md` is a legal rename a naive check rejects.
- **Subtree containment is a path-component check, not a string prefix** (D10). `/a/foobar` is not inside `/a/foo`.
- **`FileManager.trashItem`, never `removeItem`** (D10). "Delete to Trash" is the acceptance wording and the recoverable behavior users expect.
- **Renaming re-keys `expanded`, `children` **and** `watchers` for the node and every cached descendant** (D10), or an expanded folder silently collapses when renamed and leaks its watcher.
- **`renamed(to:)` must recompute `format`, not just `fileURL`** (D12). Without it, `notes.md` → `notes.txt` stays Markdown-highlighted, Markdown-previewed, and outlined.
- **Do not bump `WorkspaceSession.currentVersion`** (D13). `loadSession()` discards any session whose version does not match — bumping it deletes every existing user's open tabs. An added optional `Codable` field needs no bump.
- **Do create `.withSecurityScope` bookmarks** (D14) — they work unsandboxed (verified), so sandboxing later is an entitlement change rather than a format migration. But **never call `stopAccessingSecurityScopedResource()` when `start…` returned `false`**: the calls are reference-counted and an unbalanced stop revokes access someone else is holding.
- **One `FileTreePreferences` per process, injected** (D7). A per-window cached copy is exactly the bug already filed as #34; do not add four more instances of it.
- **`SidebarSelection` is app-target-only** (D8). If you write `import OutlineUI` inside `FileTree`, or `import FileTree` inside `OutlineUI`, stop.
- **Copy E08's row-gesture treatment verbatim** — `.frame(maxWidth: .infinity)` + `.contentShape(Rectangle())` + `.simultaneousGesture(TapGesture())`. Its comments in `SidebarView.swift` record why a plain `.onTapGesture` in a `List` row intermittently does nothing at all.
- **`FileTree` imports `FileCore`, `Foundation`, `Observation`, `Dispatch` — nothing else** (D1). No `SwiftUI`, no `AppKit`, no `Workspace`.
- **The watcher never touches an open document** (D11/§2.6). In-app CRUD does. External changes to open documents are E18's, and E18 must not have to depend on this module.
- **No `Package.swift` / `project.yml` / `ci.yml` diff** (§6). The target, the product, the test target, and the app dependency all already exist.

## Trash confirmation origin — 3 November 2026

Both Folder-menu and row-context-menu Trash actions now construct one
FileTreeTrashConfirmation before presenting their sheet. It retains the
original URL and existing FileTreeOperationContext, and checks weak origin
validity before invoking the model. Root replacement, including A -> B -> A,
window close and task cancellation cannot acquire a fresh context at response
time. Existing mutation/result propagation remains unchanged. Tests use the real
model with in-memory preferences/reader/watcher and a recording mutator; no local
system Trash or native sheet is exercised. `downstream/async-ui-publication-review.md`
records the binding source unit. This fixes delayed UI authority, not the broader
path-based mutator/external-writer race or native filesystem acceptance.

Open Folder now captures its existing controller or explicit no-document intent
before scheduling the panel. Focus changes cannot retarget it; a closed origin
cancels completion. With no document at dispatch, cancellation creates no window
and acceptance creates its own window even if a document opened meanwhile.
Gated FilePanelProviding app tests cover all four paths without a native panel;
the actual app-target execution remains hosted-only locally.
