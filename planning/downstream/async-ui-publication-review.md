# Keep asynchronous UI state tied to its original operation

## Owner outcome and baseline

A JSON preview must remain visibly busy while admitted immediate analysis is
still running. A FileTree Trash confirmation must not gain fresh root authority
when its sheet returns after root/window changes. Baseline is 47a0f424 (#573),
master remains 15c0fae2. These are focused #183/#115 review remediations in the
explicitly requested smaller JSONSupport/FileTree app surfaces.

## Evidence and binding implementation

JSONAnalysisSession.analyzeAndPublish's defer derives isAnalyzing only from the
stored debounced task. Two overlapping analyzeNow calls have no such task: the
older completion can clear the newer request's busy indicator. Track actual
immediate calls through a counter/defer, and derive busy state from pending
scheduled work OR admitted immediate work. Keep generation-based publication,
cancelled-result return behavior and the already-cancelled no-state path intact.
This follows MarkdownParseSession's existing immediate-work accounting; it does
not promise preemption or establish parser performance/worker bounds.

Open Folder also defers its ordinary-menu target lookup until after the panel.
Capture the existing controller (or explicit no-document intent) synchronously
before scheduling. Use the existing captured-application panel provider for a
no-document modal; cancellation creates no placeholder. A no-document choice
creates its own new window on acceptance even if another document opens while
waiting. A closed captured controller cancels completion. A gated injected
FilePanelProviding is a hosted-test seam, not a new public command option.

Both menu and row-context Trash code currently call beginOperation only after
the sheet completes. Capture one FileTreeTrashConfirmation before presentation:
original URL, existing FileTreeOperationContext, weak window/controller validity.
Confirmed execution checks that same context and cancellation before invoking
the existing model API. An A -> B -> A root change remains stale. Do not adopt
an ambient later selection, permit a closed origin or write user Trash in local
controls. Model mutation/result propagation remains otherwise unchanged.

The pinned swift-cmark package was inspected while reviewing parser concurrency:
on macOS its bundled config enables threading and CMARK_RUN_ONCE uses
pthread_once. The wrapper's comment claiming a plain-int-only upstream guard is
stale. Correct that comment; do not invent a new global mutex or attribute past
package crashes to this rejected hypothesis.

## Proof and limits

Run deterministic held-worker JSON tests against unchanged source first, retain
the actual busy-state assertion failure, then verify full JSON controls after the
fix. Test the real FileTreeModel with in-memory preferences/reader/watcher and a
recording mutator: confirmed original URL, root replacement/ABA, cancelled or
closed origin, and no mutation on stale confirmation. A late-context mutation
must fail those tests. Foundation-only harness sources are unchanged except test
module imports; no app, native sheet, owner preferences or system Trash runs.

Strict lint/pinned format, Compliance, unsigned compile-only app/UI targets and
complete exact-head hosted tests remain required. These are self-review lenses,
not independent final approval. Rooted filesystem mutation races, installed/native
acceptance, crash journals, performance budgets and held feature probes remain
separate; no release or master promotion is authorized by this source work.

## Folder fixture directory identity — 3 November 2026

Full ARM run 41557168954 retains two actual folder-origin assertion failures:
the admitted model root is a directory URL with its trailing slash, while the
fixture constructed its not-yet-created root with the default file hint. The
physical directory and target controller are correct; the expected URL value
does not match the real folder-panel contract. Construct the fixture root with
isDirectory: true and assert hasDirectoryPath. Keep both original model URL
equality checks and every origin/cancellation assertion; do not compare only
paths, remove equality checks or change product canonicalization. Full combined
qualification remains required. The owner's later main-transfer authorization
supersedes this document's historical source-only promotion restriction.
