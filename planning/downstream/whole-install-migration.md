# Preserve the development installation before activating MostlyText storage

## Owner summary

MostlyText uses the owner-approved `app.mostlytext.MostlyText` identity and its own Application Support root. Before ordinary models exist, copy and verify the development installation, retain an independent recovery snapshot, then activate the new working copy. Settings, workspace defaults, sessions, recovery epochs/redirects, custom themes, snippets and user automation are authoritative. Never move/delete the old installation or infer permission from a saved path. A populated final installation wins as a whole profile; preserve the development profile separately and explain how to review it.

## Baseline and boundaries

Master is `15c0fae22f7618e94c82681227057c66011be2a9`; integration starts at `975dc27d782526a92daa8d99761a14e25cc499a8`. The bundle identity is already decided in RELEASE_PATH.md section 4 (28 September), despite unchecked older #158 rows. #562 supplies the optional original-MacDown import; this required development-state preservation precedes it. No signing, Daybreak, real user-store migration, local app execution, repository cutover or release is performed here. Package convenience defaults retain their historical locations for compatibility; production receives explicit locations everywhere.

## State and ownership

AppSettings owns ApplicationStorageLocations, bounded preference snapshots, the installation actor and its MainActor defaults publisher. Reuse the existing restricted journal directory primitives. AppKit owns running-app checks and the startup presentation; the app owns admission of copied session/theme/snippet state. FileCore owns read-only recovery-ledger admission using JSONSupport, and FileTree retains unresolved bookmark records during identity migration. No new third-party dependency is added.

Capture only the allowlisted development root `Application Support/MacDown 2`, the development optional-import journal, and the development app/workspace defaults domains. Do not scan Application Support generally. Preserve the complete original optional-import journal as data; a validated complete record prevents offering that same already-completed optional import again after adoption. Unknown files stay in the retained snapshot and are not interpreted. Known disposable cache directories may be excluded explicitly. Retained backup scripts are data-only. The working Commands copy preserves only an existing owner-execute bit; commands remain explicitly user-installed and require the existing deliberate Run action. Migration never runs a script or grants a new automatic-execution capability.

The installation actor holds the new root's owned single-link 0600 advisory lock for the entire application lifetime. Its root is owned 0700, physical/no-symlink, deny-only/no extended ACL, on an ownership-enforcing volume. Source trees are opened read-only with anchored no-follow descriptors and reject unsafe ownership, links, granting ACLs, replacement or drift. Never repair existing ACLs/modes or remove source/staging data. A second participating instance cannot bypass required migration and construct writers.

State is inspect -> immutable plan -> private staging -> verified atomic directory publication -> per-domain defaults readback/acknowledgement -> immutable complete -> ordinary owners. An incomplete stage is retained and a fresh private stage may be used on retry. An existing published generation must match the plan before recovery proceeds; a differing object is preserved as a conflict. Completed records are historical and do not compare mutable working files or reapply preferences over later edits.

The published generation contains independent `Source` and `State` trees plus raw preference snapshots and the previous editor-import journal. Source/State are ordinary copies, never hardlinks. New runtime stores use only State. A single exclusive directory rename publishes the complete generation. Flush files and directories and recheck source snapshots around copying/publication. UserDefaults and files are not an atomic transaction: compare each saved domain against its exact captured before/desired typed digest, set only a still-matching before value, require readback, then durably acknowledge. Retain conflicting later values. An acknowledgement prevents replay after later edits/reverts. Check the closed development app and fresh defaults immediately before a first preference write.

## Admission and conflicts

Strictly inspect copied settings, canonical sessions, recovery ledgers, snippets and themes before activation. Unknown/future/malformed authoritative formats stop required migration, with originals and staged copies retained; they are never turned into empty stores. Existing final state is retained without importing development settings into it. Preserve a separate development backup and expose a deliberate Finder review action. All authored text and IDs/epochs remain byte-identical; no documents outside Application Support are copied or normalized.

Bookmark bytes and lexical labels survive. Resolution under the new identity grants no authority by itself. Keep unavailable structured entries visible, retain opaque unresolved records, and route an unresolved recent-item action to a user chooser rather than opening a stored path. Native TCC/security-scope behavior remains an exact-account/candidate acceptance gate.

## Resource, failure and cancellation rules

At most 512 entries, depth 8, 64 MiB per file and 512 MiB total source bytes; the immutable plan is at most 256 KiB. Preference snapshots retain the existing 1 MiB admission budget per domain. Copy one bounded file at a time, with independent source/working writes. Detect case/name collisions by exclusive creation; never overwrite to make a copy fit. Failed stages remain private. Source drift, unsafe storage, unknown records, disk-full, sync/readback failures and competing writers yield a recovery-required startup with Retry/Quit/review actions, never Continue into incomplete state. Cancellation before completion leaves a resumable journal; no automatic rollback overwrites a third value.

## Production construction and interfaces

One ApplicationStorageLocations value supplies session, Recovery, Themes, snippets and Commands, plus final app/workspace domain names. Inject these into AppDelegate, coordinator snippet/palette/filter routes and every production store. Keep app/UI-test hosts on their existing isolated/bypass path. Determine first-run state after migration, not before preference adoption. Required installation migration must finish before #562's optional import; optional conflicts can still be skipped only after required state is safe. Publish normal-launch readiness only after construction. Queue file opens until that point. Quit during required work cannot run a session publisher; safe review/error states can quit without touching existing sessions.

## Remaining original-MacDown policies

Finish explicit reports for local math/inline-dollar behavior, Graphviz, Mermaid, explicit TOC markers and fresh update-channel consent. These are capability/semantic explanations, not new Boolean destination keys, imported scripts, network endpoints or no-op switches. No old updater feed/key/channel is replayed. Bind all policies to the exhaustive source-backed declaration record and test true/false/type-invalid cases.

## Verification and completion

Use disposable internal-disk trees and unique synthetic defaults suites only. Cover exact byte/ID/epoch/theme/snippet preservation, missing and populated targets, source/defaults drift, partial per-domain publication, each injected copy/publication/ack boundary, later edits/reverts, unknown/future records, symlink/hardlink/ACL/mode/replacement/case-collision refusal, lock ownership, cancellation and independent-copy mutations. Test bookmark refusal/retention without granting a stored path. Run focused Debug/Release harnesses, strict lint/format, Compliance, compile-only local app/tests, full hosted package/app/Debug/Release/pin checks and self-review before integration-only merge. Preserve initial failures. Real installed-state/native/VoiceOver/signing acceptance and public promotion remain open.

After this tranche merges, the owner requested merged-branch cleanup and a source/evidence audit of the work remaining before integration-final can merge. Preserve unmerged work and protected branches; record deleted refs for recovery.

## Managed references and restart-safe metadata completion

An open managed file (notably snippets.json) can still name the development root. After publishing the independent working copy, relocate only managed session paths and structured recent bookmarks into that owned root. Preserve ordinary document paths, tab IDs, selections, encodings and recovery epochs. Use the existing durable recovery migration/redirect mechanism for a changed file document ID before conditionally publishing the session against its exact captured raw revision. A restart repeats the deterministic mapping and can find recovery through either identity. A separate immutable path-acknowledgement prevents replay over later explicit user choices. Bookmark grants are recreated only for verified descendants of the newly owned working root; outside bookmarks remain raw data and must resolve or request a chooser.

A source change before any destination preference publication can retire only unchanged transaction-owned output into private retained names under the same held root lock, then replan. Never retire/replan after preference acknowledgement or a partial preference write, or over a modified working generation. No retired stage/plan/generation is deleted automatically.

## Validation record

Initial compile, fixture BOM-decoding assertions, canonical managed-file identity, and local formatter-version failures are retained in the external evidence directory. BOM assertions now compare exact Data; managed target URLs use the same standardized identity as ordinary FileDocument restoration. Formatting uses CI-pinned SwiftFormat 0.63.1. The helper harness contains no executable/app entry point or AppDelegate and uses only disposable internal-disk trees and unique test defaults domains. It does not execute app-target tests or confer native acceptance.
