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

## First viewport execution

The 0a7aecfa Debug and Release consumer runs execute all 33/34 selected
functions. The new viewport fixture times out before establishing its initial
overflowing, fully rendered Preview; all image, resource, parsed-revision and
network controls pass. No scroll-preservation result is inferred. Initialize
the owned application's accessibility client as the existing native heading
fixture does, and retain bounded load-ID, scroll-geometry and native-text
diagnostics on the unchanged five-second readiness failure. All thirty row
markers, real overflow, container identity, offset and focus checks remain.

## Retire a hidden pending parse frame before activation

The e476aa51 candidate now qualifies its three consumer paths, four native
counterfactual/restoration phases and full unchanged CI retry. The original
full-run signal 11 remains unclassified; the retry does not close issue #15.
The branch now incorporates qualified PR99 source 37e6fde0 so the next combined
qualification includes the actual theme activation rather than deferring that
integration until after its merge. Production routing remains held.

Orthogonal lifecycle review found that onDisappear captures only the slot that
matches the latest parse identity. A new parsed identity makes that filtered
value nil before its replacement task runs; hiding Preview at that point can
leave the previously admitted load alive. Capture the existing stored context
for retirement, still using matching-context retirement so an old subtree can
never revoke a newer renderer's load. Add a mounted native same-turn replacement
then hide control that retains the actual loader, forbids a newer load from
starting and requires that retained loader to deny a subsequent real image read.
The actual Textual color environment is constructed only through its testable
immutable initializer; no reader, image decoder or grant is substituted.
Reintroducing the filtered-context lookup must fail that exact control, and
restoring the complete source must pass. Keep all original consumer, network,
quota, revision, scroll and phase deadlines unchanged.

## Keep complete native mutation proof within the original job limit

Combined source c63e8230 passes all 35 Release consumer functions/12 suites,
both live network controls and zero denied requests. Its initial universal
app/test compilation takes 17 minutes 36 seconds. The native revision omission
fails as intended, exact restoration passes all three mounted functions, and
the viewport omission fails as intended. The 35-minute job then expires while
building the viewport restoration; no disappearance pair or complete result is
claimed. Preserve its complete logs and partial artifact.

Run each of the three actual mutation/restoration pairs in its own hosted job
in both configurations. Every job still builds the actual app, executes the
complete unchanged 34/35 consumer selection, network and original ownership
controls, and verifies immutable source/pins. Bind the selected pair in the
receipt and require exactly its two ordered phases. Overall qualification
requires all six matrix jobs. Keep the 35-minute job limit and all existing
900-second build and 600/660-second execution limits unchanged. This partitions
repeated whole-module rebuilds; it removes no assertions or required proof.

The same c63e8230 Debug job completes all 34 functions/11 suites and all six
actual mutation/restoration phases. Independent review verifies 1,592 source
hashes, all 24 pins, the working network controls, zero denied requests, exact
mutated/restored host bytes, distinct mutated executable hashes and identical
restored executables. In particular the filtered-context disappearance mutation
fails the retained-loader denial while both unrelated mounted controls pass;
restored source passes all three. This establishes the lifecycle defect in
Debug. Release's three recorded partial phases and complete positive selection
remain partial proof; the new six-job matrix must qualify both configurations.

Each pair also records the original pre-mutation application executable hash.
The changed executable must differ, and its exact restoration must equal that
original hash, in addition to the existing source, selected tests and pin checks.
Do not require independently built jobs to have byte-identical executables;
qualify each job against its own unmodified build.

## Diagnose unrelated mounted-copy failures before activation

The 7f2fcb3c full CI passes 3711 package functions/532 suites and 683 app
functions/146 suites. Both math/heading/status configurations pass 29/9.
The Release disappearance pair also passes all 35 consumer functions/12 suites,
its intended mutation and exact executable restoration, independently verified
against 1593 inputs and 24 pins. The Debug viewport pair passes.

Two separate Debug pair jobs instead expose failed mounted-copy positive
controls: HTML contains the image's alt text but no PNG. One revision mutation
also encounters its intended new-frame failure; its unrelated generation-copy
control fails, so the pair is correctly refused. The disappearance mutation
fails only its intended assertion, but exact restoration later fails the
new-parsed-frame copy control. Preserve both failed artifacts; neither is
qualified by the earlier complete c63 run or the successful initial 34/11
selection. No native copy deadline or expected PNG is weakened.

Add failure-only diagnostics before deciding on a production fix: distinguish
initial versus replacement copy, record the actual selected loader's read/decode
result, exact generated PNG bytes, current load ID/ledger and disappearance
state, and inspect every real native text-interaction descendant's copy output
and visibility. This must identify whether the failure is token revocation,
image decode, retained-byte readiness, an obsolete view selected by the fixture,
or actual current Textual export. Diagnostics must still fail the original
copy assertion and preserve all input and ownership checks. Do not infer an
uninitialized/transparent-PNG cause, a pasteboard-service cause or a production
repair from the current evidence. Native execution remains hosted only.

## Failure-only actual selection/layout readback

Source 2ad548a7 preserves label-only native copy failures in Debug disappearance
restoration and Release revision restoration. Their initial complete selections
pass; actual restored source/executable hashes match the original. Both failures
have a current recorded loader that can read/decode the unchanged generated
fixture, retained input 152/reserved input 0 before diagnostic read, and one
visible 8×19 native text interaction view copying only its label. The actual
attachment's selection/layout/copy state remains the unanswered boundary; this
is not proof of a loader, model, PNG, pasteboard or scheduling cause.

Add only failure-path test diagnostics. Read the actual Textual interaction's
selection model and its actual layout collection through test-only access;
compare cached and freshly materialized attributed content, original line
fragments and actual attachment-run counts. For actual selected attachment
values, record one bounded PNG result with a 1 MiB diagnostic cap (the fixture
is 8×8); never substitute it for the native copy assertion or lift production
limits. Introspection failure is explicit, not a fabricated empty result.
No model/layout setter, loader/authority bypass, source/PNG mutation, deadline
change or qualification retry is added. Preserve the original failed verdict.
Unsigned universal Release compilation succeeds; native failure evidence must
still be collected in the hosted job, after useful current qualification jobs
finish. Production activation remains held for all required consumer controls.

The final branch also carries only the reviewed standalone export-sheet fixture
ownership correction from d9c3cc70. Swift-owned windows must disable automatic
release on close under AppKit's documented ARC contract. Keep the real sheet
presentation/cancellation/detachment checks and all deadlines; no production
window policy or historical crash-cause claim follows. This avoids leaving a
known test-host lifetime violation while qualifying the complete app suite.
