# Activate document-bound Preview resources

## Owner summary

Saved HTML and Markdown images must read only a folder explicitly selected for
that document window. Switching documents, Save As, root replacement or closing
the window must revoke old delivery before the new identity is visible. This
continues MostlyText #13 and the reviewed issue-121-directory-grant-proposal.md;
it does not authorize owner-account launches or waive signed permission checks.

## Live baseline and contracts

Main ee45cc25d43c9cf6b067ad4d2674312a96f7cb1e contains the complete inactive
reader, directory backing, pre-publication invalidation, image decode/export
limits, immutable WebKit host and pinned bounded Textual exporter. Production
Markdown still uses Textual's ordinary loader; HTMLPreviewPane still uses the
legacy HTMLPreviewView. WindowController already owns/revokes the window state.
The explicit folder chooser edge records a typed selection but is not visible.
PR99 separately qualifies theme semantics; incorporate its verified merge and
requalify combined source before merging this branch if it merges first.

Keep the existing dependency direction, budgets, containment syscalls, saved-only
HTML behavior, source bytes, opaque window/load identity and synchronous revoke
ordering. No new dependency or signing settings. A selected file never grants
its inferred parent. A failed/cancelled/stale folder choice leaves resources
denied and readable source intact. Ordinary editing must remain available.

## Ordered slices and proof

1. Requalify all three inactive consumers on current hosted macOS26 in both
   Debug and optimized Release: real Textual mounted image copy/revocation;
   ImageIO dimension/frame admission and bounded export; immutable WebKit
   generation/response/stop/late-read behavior; grant and worker lifetimes.
   Add actual hostile-content network observation with an independently live
   loopback HTTP control. Preserve first failures. No visible chooser yet.
2. Only after those focused proofs pass, route the production Markdown and HTML
   hosts through those same consumers. Preserve all existing heading/math,
   diagnostics, links and source/rendered controls. Add the localized, keyboard-
   accessible Allow preview resources action to the document's own window;
   freeze its origin before the panel and reject stale results after awaits.
   Show denied resources deliberately, without inferring directory authority.
3. Add actual production-routing, same-text Save As, A/B/A and held-completion
   controls. Re-run exact combined full CI/native Debug/Release, strict tools,
   source/pin receipts and orthogonal review before integration.
4. Record remaining intended signed-app permission, hostile native owner,
   multi-window/WebKit RSS, and final Release dogfood gates on #13/#8. Source
   qualification cannot close the whole issue while those remain unverified.

## Execution and evidence boundaries

Native tests execute only on hosted macOS26. Local work is source inspection,
strict tools and unsigned compile-only. Reuse the exact-app watchdog with
600-second execution and owned process/stack evidence, not broad process kills.
Each native receipt binds all tracked app/package/test/workflow inputs and all
24 immutable dependency pins, configuration and test-only conditions. Require
all selected suite/function counts so an Xcode restart's partial pass is refused.
Opt-in 4MiB HTML hardening observations remain raw phase/process RSS, not a
WebKit heap ceiling or frozen performance budget. Network control and hostile
requests use only generated temporary fixtures and a bounded loopback server;
no user document or external service is read.

Stop and revise this document before changing authority, source-preservation,
containment algorithms, concurrency budgets, release entitlements, or weakening
any assertions/deadlines. The existing directory proposal remains binding.

The app test target additionally compiles the two original Preview package
fixtures by source path (decoded/output-export budgets and Textual authored URL
interception), preserving their exact bytes and actual module imports. The
focused hosted gate selects those same controls, including optimized Release;
there is no adapted image loader or duplicated implementation. Full source/pin
receipts include these original package files and the project declaration.
