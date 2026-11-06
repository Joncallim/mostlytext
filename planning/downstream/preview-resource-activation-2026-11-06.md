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

## Parsed-frame lifetime refinement

The inactive Markdown host originally keyed its subtree only by model edit
generation, document identity and grant epoch. A completed parser revision can
change while that model generation stays constant: the model was edited before
the older parse displayed, or unchanged text is reparsed with new options. Add
parser UUID, actual parsed revision and its exact source SHA to the immutable
resource-frame key before connecting the live renderer. An unbound parse never
starts a resource load. Keep the model-generation check as a separate live-owner
guard; neither a parser ID nor equal-looking text replaces directory authority.

A mounted control reparses identical authored image source twice without any
model mutation, updates the real Textual subtree, and requires a fresh resource
load ID. The existing generation-replacement/copy/revocation control stays. A
revision-omission mutation must fail the new control and exact restored source
must pass before this refinement is considered qualified. It remains an
inactive-consumer change; do not expose production routing or the chooser
until all three consumer prerequisites and the final combined checks pass.

## First optimized consumer findings

Source da4b97f5 executes all 32 Release functions/11 suites and reports four
assertions in two tests. The generated 65536x65536-header PNG is invalid to
ImageIO itself: its properties omit width/height before the Preview decoder can
inspect them. Replace that fixture with genuine compressed 8193x1 and 4096x4096
rasters: the first exceeds the existing axis cap, the second the decoded-byte
cap while still fitting the encoded-input cap. Require their actual ImageIO
metadata, unchanged rejection and zero retained decoder capacity. This repairs
the fixture's domain; neither production limit changes.

The original global decoded-budget test observes only 64MiB instead of 128MiB
because an array's count does not keep its unused reservation elements alive
under optimized ARC. Explicit withExtendedLifetime scopes now retain both real
arrays through the global-cap checks and retain the second through release of
the first. Every original full-cap, rejected-admission, returned-capacity and
resumed-admission assertion remains. The original canonical package fixture is
corrected; the app target still compiles that same file by source path.

The independent URLSession and ordinary WebKit controls both reach the listener;
the real secured hostile page finishes with zero denied requests. Existing
grant/worker, late-read/reentrant-stop, native saved-view replacement, mounted
copy/revocation, valid image, multi-frame and Textual interception controls pass.
The 4MiB/three-retained-load Release phase records 155.258708ms and process peak
RSS 326959104 before/after, not a WebKit heap or performance-budget pass. First
failure artifacts and source/pin receipts remain under da4b97f5; no whole
consumer qualification or activation is claimed from this failed run.

## Stable Preview container during resource replacement

The inactive host also placed identity modifiers around its entire content,
which is the caller's whole Textual preview and ScrollView. Changing a resource
load must not replace the outer scroll container, clear its measured-height
state or move keyboard focus. Keep the host/content structurally stable; the
existing BlockView already keys each actual StructuredText/WithAttachments
subtree by resourceLoadID and installs the deny-by-default image/emoji loaders.
That is the required cache replacement boundary. Add mounted native proof that
a delayed parse publication (with unchanged model generation) creates a new
load while retaining the actual NSScrollView, nonzero scroll offset and responder. Keep all byte/publication
revocation guards. If actual native layout still loses its position, inspect
that behavior before activating the consumer; do not weaken the scroll check.

The first Debug consumer job compiles the real app/tests but never executes a
function: macOS Bash 3.2 rejects the empty EXTRA_TESTS array under nounset. Its
zero-byte probe log and failed strict result check are retained, not a Debug
pass. Use one explicit scalar selection: skip the opt-in maximum-source suite
in Debug and select it in Release. This preserves strict shell settings and
all intended per-configuration tests without an empty-array expansion.
