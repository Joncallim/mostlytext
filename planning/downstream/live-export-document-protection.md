# Preserve live documents while exporting frozen inputs

## Owner outcome and baseline

An export may finish from its frozen original source/root after Save As, but it
must never overwrite a document opened while rendering. Keep source-window close,
logical-tab removal, cancellation and destination-revision refusal effective.
Baseline is 0f48fa18 (#571) after destination admission #569 and parse reuse #570;
master remains 15c0fae2. This implements the existing #117/#118 lifetime contract,
without enabling the optional validated route or local app execution.

## Source-confirmed gaps

Destination admission checks the document set only before the contribution await.
A later document can open the unchanged output without changing its disk stamp,
so final primary promotion still succeeds. Conversely ordinary export reuses the
strict validated lease registry: Save As or a folder grant change revokes even
an already frozen export, contrary to #117's explicit retained-root behavior.

## Binding implementation

Use a MainActor registry of weak export leases and retained admissions. Register
before any render await and remove with defer. Before controller-pool/staged-CLI
publication and before an existing controller's tab file identities change,
check incoming URLs plus previously observed device/inode identities against
active admissions. Revoke aliases synchronously before those documents become
observable. Final publication and revocation keep the existing shared lease lock.
Do not cancel exports merely because an unrelated file opens or focus changes.
Keystroke-only writes do not trigger filesystem alias checks. Cover inactive tabs,
pre-populated restored controllers and unlinked retained file objects.

Add a separate ordinary origin lease policy. Before panel acceptance it is strict.
After source, source directory capability and presentation are frozen, promote
only that ordinary lease to tolerate identity/folder changes while the same
logical tab remains active. Active-tab switch/removal and window close still
revoke; disabled validated leases always retain their current strict behavior.
No live snapshot retargeting, ambient window lookup or source normalization.

## Proof and limits

Foundation/POSIX tests exercise registry exact-name/hard-link/missing/unlinked
identities, unrelated opens, weak cleanup and publication cutoff. Hosted app
controls hold the real contribution parse, publish a new/inactive document or
controller targeting the output, and prove original output preservation. A
post-freeze Save As must finish from the old text/root while close and pre-freeze
identity changes continue to cancel. Preserve every existing origin/snapshot
assertion. Disable registry revocation for a genuine failing-before control.

Run strict lint/pinned format, source-identical non-app tests Debug/Release,
Compliance, unsigned compile-only app/UI targets and complete exact-head hosted
checks. Local app/app-target execution stays held. This is in-process document
coordination, not arbitrary external-writer/root-membership exclusion or filesystem
compare-and-swap. Crash journals, printer scratch ownership, native acceptance,
empirical budgets and final independent release review remain separate.
