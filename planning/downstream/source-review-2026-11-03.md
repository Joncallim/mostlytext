# Source review across export, CLI and delayed UI state

## Owner summary and provenance

This review found concrete input-work, document-lifetime and delayed-UI defects
in source that can be repaired without Daybreak or a separate account. The
candidate combines those repairs with single-parse export reuse. It must receive
complete hosted validation at its exact head before integration. This is a scoped
orthogonal self-review using several distinct questions, not an independent
reviewer, final whole-repository #115 sign-off or native release acceptance.

Integrated baseline: cf3f8b8613f7e0772642c7d9573e063f19de7ef4 (#569).
Preserved source units: ffb5f2b0 (#570), 0f48fa18 (#571), d18ca0f3 (#572),
47a0f424 (#573), plus this candidate's JSON/FileTree changes. Master remains
15c0fae22f7618e94c82681227057c66011be2a9. Git history and the PR identify the
final candidate; manifests bind local controls to unchanged production sources.

## Separate review questions and findings

| Question | Source counterexample and severity | Repair and discriminating evidence |
|---|---|---|
| Can a small final manifest hide excessive input work? | P2: query/percent variants and distinct hard-link aliases repeatedly read/hash identical payloads outside the distinct-resource quota. | Exact-byte parsed-path caching plus composition-wide attempt/actual-byte accounting. Cache/accounting mutations fail actual assertions; failed, mutated and non-image reads consume work. |
| Do Unicode spellings retain their own resource identity? | P2: Swift String dictionary keys merge NFC/NFD authored references, undoing a byte-exact path policy and collapsing audit entries. | Byte keys through raw-reference lookup and diagnostics, canonical payload reuse, and a complete sorted referenceMappings audit list. A normalization mutation fails the two-frozen-payload/audit test. Existing referenceMap stays a documented compatibility view. |
| Can rendering overwrite a document opened after authorization? | P1: opening an unchanged output while parsing does not alter the captured disk stamp; authorization-time checks alone miss it. | Weak lease/admission registry, synchronous controller/stage and tab-backing publication hooks, retained device/inode checks and the existing promotion cutoff. Suppressing revocation overwrites the fixture and fails both preservation assertions. Hosted controls cover active/inactive/pre-populated/staged/unlinked routes. |
| Does Save As splice or wrongly invalidate frozen inputs? | P2: the strict validated lease cancelled ordinary export even after source/root capture, contrary to #117. | An explicit frozen ordinary phase; same-tab Save As keeps the old capability/text, while close/tab removal still revoke. Hosted held-parse test uses different old/new image bytes and the real Save As API. Disabled validated behavior stays strict. |
| Can CLI metadata block before its limit applies? | P2: FileHandle opens a FIFO or follows a leaf symlink before the Info.plist byte check. | Nonblocking/no-follow bounded regular-file helper, descriptor/named identity and time/size checks. Real FIFO, mutation/replacement, boundaries and descriptor controls pass; the prior path read fails the symlink assertion. Hosted public-locator test preserves the original signature/container tests. |
| Does old JSON work hide current work? | P2: an older analyzeNow completion or cancelPending clears isAnalyzing while another admitted immediate worker is running. | Immediate-work count plus scheduled-work state, with existing generation publication unchanged. Three held-worker tests fail on unchanged source, then pass after repair. |
| Can an old Trash sheet acquire new root authority? | P2: both menu paths capture beginOperation only after confirmation, allowing an A -> B -> A root change to refresh the old intent. | Capture source/context and weak origin before presentation; check cancellation/current ownership before the model call. A late-context mutation invokes the recording mutator and fails actual ABA assertions. No local system Trash runs. |
| Can an Open Folder result retarget another window? | P2: ordinary-menu completion performs a new ambient controller lookup after the panel await. | Capture existing origin or explicit no-document intent before scheduling; closed-origin completion cancels. No-document cancellation creates no window; acceptance creates its own window. Four gated hosted controls exercise target drift, close, late documents and cancel. |

## Less-reviewed surfaces and rejected hypotheses

Read actual CLI argument/input/exchange/locator/launch code; FileTree app menu,
row-confirmation and model/context paths; JSON scanner strings/values, duplicate
keys, outlines and analysis publication; Preview link resolution, geometry
batching, HTML policy/CSP and image-loader accounting. These source inspections
are separate from the native/network/accessibility proofs assigned to their
owning issues.

The cmark-global-initialization hypothesis was rejected from the pinned sources:
swift-cmark 0.8.0 revision 924936d0427cb25a61169739a7660230bffa6ea6 enables
CMARK_THREADING for macOS and maps CMARK_RUN_ONCE to pthread_once. The wrapper's
plain-int-only comment was stale; only that comment changes. This does not
explain or waive earlier Neon/WebKit failures, and no extra global mutex or
unrelated dependency update was introduced.

Preview geometry callback ordering still needs the mounted #520 probe: simply
rejecting all measurements outside the last reconciled IDs could also drop
legitimate initial callbacks before onChange. No speculative guard or held
presentation activation was made. #121's CSP/resource policy source is not
proof of actual network denial. Existing raw-link/math/TOC limitations remain
owned by #116/#117/#121; no source-only pass closes their native gates.

## Combined evidence and merge rule

The combined private harness executes 267 tests in 30 suites in Debug and
Release. Manifest-listed production sources are copied unchanged. App/CLI helper
test assertions are unchanged with only module imports adapted; the established
unused validated-SVG receipt DTO and theme-only fixture helper remain explicit
exclusions. Real pinned cmark/Markdown/Yams and the real Foundation/POSIX reader,
publication, JSON and FileTree model run. Preferences/reader/watcher/mutator in
confirmation controls are in memory; no app, owner store or system Trash runs.

All initial source, harness, lint and proof-check failures remain in the external
evidence directory. The first JSON/Trash log-proof scripts used overly specific
rendered-message text; readback confirms the original actual assertion failures,
without dropping or rerunning them into a pass. CLI, cache, accounting, Unicode
and lease negative controls likewise fail their intended assertions.

Strict lint, pinned SwiftFormat, Compliance/inventory and unsigned app/UI-target
compile-only checks are required. The final generated project must include the
new FolderPanelOriginTests file. Local compilation is not app-test execution.
The complete hosted package/app suites, locked Debug/Release app/mostlytext builds,
app/UI test compilation, pins, lint and Compliance must pass at the final exact
head. GitHub runner-acquisition failures ran zero build/test steps; preserved
annotations distinguish them from functional failures. A single combined ready
candidate replaces duplicate queued stack checks; no merge uses partial CI.

## Remaining work and qualification boundaries

Authenticated export crash journals/repair and safe printer scratch ownership
remain open; bounded retention is not automatic recovery. Complete arbitrary
external-writer/root-membership exclusion is not proved by revision prechecks or
this process's locks. FileTree's canonical path checks are not descriptor-rooted
mutation proof. Parser worker ownership/performance still needs its own focused
reproduction and implementation where feasible; this review does not turn an
actor's reentrant await into a serialization guarantee.

Continue these source units under #118/#183/#203 as their prerequisites permit.
Mounted preview/math/Quick Look/PDF and actual filesystem/UI acceptance retain
their named probes and safe-account execution hold. #519/#520 stay held. Work
budgets are provisional pending Release calibration. Final languages, VoiceOver,
signed installed CLI/update/migration/artifact evidence, independent final
review, repository cutover and public promotion remain downstream. Nothing in
this report closes a broader issue or authorizes master/release promotion.
