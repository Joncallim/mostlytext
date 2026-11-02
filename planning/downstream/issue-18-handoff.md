# Issue #18 / E17 — Stateful installation, CLI, updates and release

## 2 November 2026: production optional editor import

The [production import architecture](production-editor-import.md) supersedes the older pending activation/font/theme statements below. The application now runs the optional consent/journal recovery step before constructing mutable settings/theme/session/document owners. Exact representable installed fonts and the three reviewed Boolean mappings are eligible for explicit per-field selection; legacy style names have no exact aliases and never alter current theme storage. App/UI-test hosts bypass real-domain import. Whole-install identity migration, native/private-candidate evidence, final localization, signing and public release remain separate gates.


## Owner summary

Make the finished editor installable and updatable without losing the state accumulated in development or original MacDown. Deliver the promised open/stdin/--wait CLI, prove signed updates with real state and promote only the same artifact that passed final verification. Distribution is not another feature or onboarding redesign.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md), [readiness review](READINESS_REVIEW.md) and [release sequence](../RELEASE_SEQUENCE.md). Complete E22 first. E23 owns final theme/Finder/artwork integration; #53 owns settings compatibility and legacy preference conversion. No current E22 branch or live release infrastructure is altered by this plan.

## Reconciliation and settled inputs

The CLI is still a placeholder except formats listing. AppDelegate eagerly constructs production stores before a migration barrier; its first-run key includes the development identity. WorkspaceSession's convenience loader conflates missing, corrupt and unknown versions as nil. Those are not safe migration admission signals. Current EditorSettings also has the new required showsStatusBar field: #53's known-old-schema decoder must run before any fallback is persisted.

MostlyText is the settled public name; mostlytext.app and mostlytext.dev are owned, not mostlytext.org. Technical bundle/extension/CLI/update/storage identities are separate explicit inputs. Consume the latest approved identity/design register, retaining actual waivers as waivers. Do not restart naming, invent bought domains, claim a trademark clearance or generate replacement branding here.

ReleaseIdentity is a versioned manifest of actual public identifiers/URLs, supported OS/architecture, theme UTI/extension, defaults/support/recovery migration namespaces and public update key. Fail on placeholders or mixed namespaces. Store no private credentials. Unavailable identity/signing/account inputs block dependent packaging, not independent implementation. All application-side release UI/strings land before final E16.

## Bootstrap and non-destructive state migration

ApplicationBootstrapCoordinator owns inspecting -> migrating/consent/recoveryRequired -> ready. Defer normal persistent store writers, session restore and mutable settings/theme models until compatible state is ready. Queue a bounded set of legitimate file/CLI requests and drain them once without losing first-run intent. Target only known placeholder windows during cleanup, not every non-document window that could include onboarding/migration UI.

Inject one ApplicationStorageLocations value into all stores. Allowlist actual previous development namespaces; do not recursively scan the user's Application Support. Classify authoritative settings, workspace/recent roots/bookmarks/aliases, tabs/selection/layout, untitled/dirty recovery bytes, recovery epochs/redirects/pending actions and E23 custom themes separately from disposable render/index caches. Preserve E22 snippets and any durable user-created automation files when their final storage exists; never classify them as a cache because they are not recovery text. Copying scripts does not execute them or auto-grant new trust. Unknown data is retained, not run or silently discarded.

Use #53's compatible typed settings decode first. A known older domain gains defaults only for newly missing fields; existing false/default-valued preferences remain deliberate. Missing is not corrupt or future-schema. Unknown session/recovery/preferences cannot be adopted as empty and overwritten on the next launch. Normal legacy-MacDown import remains optional consent; development-state preservation is required. Multiple divergent source installs require explicit conflict resolution, not newest-timestamp selection.

Use copy -> verify -> publish. Snapshot relative names/types/sizes/hashes/schema and identity relationships; preserve valid UUIDs/recovery epochs. Stage under a restricted owned directory, validate cross-record references and before/desired digests, then activate through a journaled small pointer/manifest. Never destructively move first or automatically delete old authoritative namespaces during initial migration. Existing final state wins; identical records deduplicate; conflicting unsaved branches remain separately recoverable. Do not wholesale replace a populated final namespace.

A new-product lock serializes its own bootstrap/settings writers, not an old app that does not honor it. Detect old running installations without killing them; request they close for a coherent migration. Recheck source identity/digests around staging and before activation. Source drift aborts/replans only owned staging. Retaining old bytes is required even after success; a later old-app launch cannot destroy the only copy through this migration. Do not claim an in-process lock fences arbitrary same-user writers.

Preserve bookmark bytes/URLs but verify authority under the new identity. Refresh valid grants, request reauthorization when needed and keep inaccessible roots visible without losing other restored documents. A saved path is not a permission grant. Theme retries reuse journaled stable IDs via E23 Replace/Copy/no-op rules.

Journal per-record before/desired digests and exact completion acknowledgements. Retry already-desired output once, write only still-matching before values, and preserve any third-party/user changed value as conflict. Rollback touches only unchanged transaction-owned output. Cover disk-full, partial permissions, copy failure and crashes before/after every boundary. UserDefaults/files together are not atomic; use #53's single serialized writer and read-back rules. Original source files and encoding/EOL/BOM/final-newline are untouched.

## CLI contract and transport

Keep formats registry-backed and add pinned swift-argument-parser syntax: open/default file arguments, `--` escape, `-` stdin, --wait, --help and --version. Paths resolve against the captured caller directory; spaces/newlines/Unicode/metacharacters remain structured data, never shell interpolation. Missing files report failure rather than being created silently.

Bundle the CLI inside the signed app, with optional explicit user-created symlink in a user-owned bin directory. Resolve that symlink to the enclosing installed app and launch that verified path via NSWorkspace/LaunchServices. Do not search PATH for an app, edit shell profiles, overwrite an existing executable, auto-run sudo or install a privileged daemon. App and embedded CLI update together.

Use a per-user Unix-domain socket owned by the running app, with a short hashed-identity endpoint under the OS user-runtime directory. Check owner/type/no-follow parent, 0700 directory/0600 socket and sockaddr_un length. Verify peer UID in both directions. No TCP endpoint. This prevents other-user access, not hostile same-UID impersonation; self-reported bundle/version fields are compatibility data, not cryptographic identity proof. File-opening authority remains the normal user/app boundary.

Socket instance ownership is explicit: an advisory instance lock plus live connection/handshake identifies the owner. Never unlink an endpoint simply because one connection timed out; preserve a possibly live instance. A stale endpoint is removed only after the owning instance/lock and exact endpoint identity are revalidated, with exclusive replacement. Simultaneous app launches cannot each unlink the other's socket. No arbitrary-path deletion from client input.

Protocol frames have a fixed bounded length prefix, version/type and request UUID. Metadata is strict UTF-8 JSON; stdin is a separately length-bounded byte stream with explicit termination. Handle partial reads/writes, EINTR, EOF and cancellation. Reject oversized/overflow lengths before allocation, unknown types/fields, malformed text, and reused UUIDs with different payloads. Initial limits: 64 KiB metadata, 32 paths, 32 MiB stdin, eight admitted requests and 128 wait subscribers plus a bounded replay table. Reserve bytes/slots before reads, release on actual completion. Slow clients have finite handshake/input/ack deadlines; --wait itself has no short editing timeout.

Nonterminal pipe with no files or explicit `-` creates an untitled Markdown document; an interactive bare invocation does not block on stdin. Decode stdin strictly under the documented CLI text encoding, with an explicit error for malformed input; no lossy replacement. Admit it through normal editable/recovery-backed document APIs, not a temporary saved filename. Acknowledge only after source/recovery admission succeeds. A disconnect must not delete accepted source.

### Exact open/wait linearization

On MainActor, create a request receipt and reserve its wait subscription BEFORE a newly opened document can close or an already-open document's lifetime can end. Under one controller-owned transaction, resolve/open/dedupe targets, attach subscriptions to their logical lifetime IDs, then publish the open acknowledgement and ordered terminal events. If a target closes before the ack reaches the client, the receipt retains its terminal result and sends it after the ack. Do not perform 'open, await, subscribe' and miss the close.

Document lifetime is not a pathname or Save As document ID. E22/#120 source-to-destination transitions must carry the stable CLI logical lifetime through the existing controller lifecycle; do not keep an obsolete FileDocument alive merely to wait. Save alone does not finish --wait, Save As does not finish it, cancelled close keeps waiting, confirmed close/discard or successful safe application termination completes it exactly once. Multiple waiters are independent. --wait does not promise changes were saved to the original file.

Client SIGINT/disconnect removes that client's subscription only. Crash/lost connection returns unavailable/nonzero; do not silently relaunch/replay stdin across app instances. Within one live instance, bounded same-UUID retries return the same receipt and never duplicate insertion; changed payload is rejected. Expired receipts cannot be used to promise exactly-once processing forever. Preserve terminal receipts until acknowledged or bounded expiry, without retaining closed document models. Stable exit codes distinguish usage/input/open/unavailable/interrupted; human-readable diagnostics are localized without changing machine protocol codes.

## Updater and privacy

Initialize one SPUStandardUpdaterController after bootstrap. Check for Updates and all migration/updater application copy enter catalogs before S/final E16. Keep optional system profiling off and use the framework's deliberate automatic-check consent. Update traffic contains no source text/private document paths; core editing/render/export stays offline.

Original reviewed candidate dependency is Sparkle 2.10.0 (upstream release inspected 24 September); recheck official security/release notes when implementing, pin an exact verified version/hash and record any justified update. Do not treat this document as evidence a future newest version was inspected. Pin argument-parser and all archive dependency resolution similarly.

Use supported Developer-ID Sparkle integration/nested helpers, frozen HTTPS feed/public key and separate restricted private Ed25519 key. No private key in arguments, source, logs or artifacts. Full updates only for 1.0 unless deltas are separately justified/proven. Configure supported verification-before-extraction/feed/notes protections and test them against the pinned version; no invented XML/security option. App minimum OS remains 26, not the updater framework's lower minimum. Bundle IDs and CFBundleVersion increase correctly. Test key rotation separately; do not rotate signing/update keys casually.

Private N -> N+1 rehearsal uses a controlled test feed without rewriting signed Info.plist. Verify the actual supported override mechanism or provision an isolated preproduction route for the same frozen configuration. Do not assume an override exists because a plan names it. No private rehearsal asset is added to a public stable feed. Dirty-document update termination uses existing safe close/session/recovery behavior; cancellation must not force-discard edits.

## Archive, signing and promotion

Build from a clean exact source/lockfile/toolchain and the final string-freeze digest. Generate projects from project.yml. Verify every advertised architecture; arm64 CI does not prove Intel/universal support. Audit app, CLI, Quick Look and Sparkle nested-helper signatures/entitlements separately. Keep the existing desktop app distribution model; do not add a main-app sandbox that breaks user-installed filters, or broad injection/library-validation exceptions to make unsigned tests convenient.

Archive/export with Developer ID and Hardened Runtime; require accepted notarization and inspect logs. Staple/validate the app and package the distribution DMG as appropriate. Freeze the final stapled app before creating/signing the update archive/appcast. Retain source/dependency/toolchain manifests, app tree/CDHash, nested identities, DMG/archive hashes, notary records and dSYMs. Exact-artifact tests verify actual binary paths; rebuilding/re-signing later invalidates affected proof.

Publish only after P authorization: immutable assets/notes first, downloaded hash/signature verification, appcast last. A failed promotion leaves the previous stable feed valid. Never replace bytes behind an existing versioned signed URL or force a downgrade. Corrective updates use a higher verified build. Secret-bearing jobs never run untrusted fork code. No account purchase, credential provisioning, public release or live-DNS change is authorized merely by implementing these scripts.

## Sequence and proof

The canonical [release sequence](../RELEASE_SEQUENCE.md) distinguishes S (software/UI stabilized), V (localized private exact-artifact verification) and P (separately authorized public promotion). Application bootstrap/migration/CLI/updater and all their strings are implemented BEFORE S. #115 stays open throughout final E16 and private verification. A private signed test artifact is not an authorized production RC; after #115 passes, P promotes the same tested bytes.

Use a real previously installed development/beta app with nondefault pre-E22 settings, tabs/selection, recent roots/bookmarks, untitled/dirty and conflicting recovery branches, custom themes, snippets and caches. Inventory before/after migration, relaunch/retry and prove no loss/duplication. Test original-MacDown consent import separately. Corrupt/future schemas, inaccessible grants, interrupts/disk-full and concurrent old-app detection are mandatory.

CLI corpus includes cold/warm launch, multiple/already-open paths, failures, partial frames, pipe boundary/invalid encoding, malformed UUID reuse, slow clients, stale socket/simultaneous launch, close-before-ack, Save As, close-cancel, normal quit/crash, disconnected waiters and repeated requests. Use real public CLI/app routes, not only protocol mocks.

Install two consecutive signed private candidates and perform the genuine Sparkle update with representative state retained. Test tampered/truncated/wrong-signature downloads, feed/notes verification failure, wrong bundle/build, interrupted network, read-only/translocated install, denied permissions and dirty-document cancellation. Clean-install Gatekeeper and #88's public UI/VoiceOver/HTML/PDF/Quick Look/non-English journeys use the exact signed/notarized candidate without security bypass. Claims/screenshots must match that evidence and known non-goals/accessibility limits.

## Units and completion

A. Final identity/storage intake, #53 SETTINGS-COMPAT and non-destructive bootstrap migration.
B. CLI protocol/admission tests and actual open/lifetime integration.
C. Pinned updater and every application-side release string.
D. Guarded private signing/rehearsal and exact-artifact infrastructure with actually provisioned credentials.
E. Final E16 + V evidence, #115 closure and separately authorized P promotion.

Run serial format/strict lint, migration/CLI/updater targeted and full regressions, Release app/CLI/extension builds, then real installation/update/public-UI evidence. Allowed changes stay in bootstrap/storage constructors, CLI/protocol, updater, build/release scripts and their catalogs/tests. No E22 feature redesign, source normalization, custom privileged installer or broadened release scope.

Second review adds older-settings compatibility, durable snippet/script classification, atomic open+wait registration, terminal receipt ordering, stale socket ownership and honest same-UID authentication limits. Platform/account/identity prerequisites remain recorded; no signing, migration, CLI execution or publication has been performed by this architecture pass.

## Rebaseline 2026-10-09

E17 builds two private candidates (candidate 1 for V1; the final candidate after final E16 and after the corresponding source is published). The repository cutover (#158, full-history mirror) follows #115's closure, then public promotion is separately authorised. Source-only archive publication is independent of any binary release; see `issue-148-handoff.md`.
