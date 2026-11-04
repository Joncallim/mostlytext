# Recover companion assets without adopting or deleting user files

## Owner summary

A repeated HTML export should keep its previous output usable until replacement
is committed, remember which companion files MostlyText actually created, and
retire obsolete files only when their exact ownership is proved. Unknown,
changed, copied or currently open user files must survive every interruption.
The present writer safely retains everything but has no durable companion
inventory; changed exports eventually consume its retained-file budget. This
unit completes that source contract in #11/#17. PDF/Save-panel/native parity and
Release memory calibration remain separate.

Use one authenticated pending operation and a versioned inventory inside the
existing managed directory. Reuse the private producer key, destination admission,
lease, directory gate, descriptor-relative filesystem operations and verified
quarantine discipline. Do not introduce a second renderer, reader, source format
or profile namespace. This is not a multi-file atomic transaction or a fence
against arbitrary privileged writers.

## Baseline and execution boundary

Architecture baseline: package-localisation branch b45bef13b6d2c25273eafe09009e50d20e953ee3,
including verified main 2e3af290 and the pending #50 package/catalog correction.
The implementation must incorporate the qualified #50 source before integration.
Read this with issue-118-handoff.md, export-primary-recovery.md and
export-recovery-document-protection.md. Commit this architecture before code.

Current ordinary and optional HTML paths share ExportFilePublication. Production
supplies ExportRecoveryLocation; unauthenticated/no-recovery callers retain their
existing conservative behavior. No owner-profile/product/AppKit/WebKit execution
is permitted. Tests use owned temporary directories and the established non-app
source fixture, followed by complete hosted package/app CI and locked local
compile-only Release. No native receipt is retargeted.

## Trust and ownership

A filename, content hash, public marker or decoded Codable receipt alone cannot
authorise deletion. Every owned resource was either exclusively created by this
operation or restored from an authenticated earlier receipt. Existing matching
bytes may be reused but remain unowned unless that earlier receipt also matches
the actual object. Unknown legacy entries remain preserved and count toward the
retained quota. Keep the existing v2 marker/primary-name collision policy; do not
adopt unfamiliar directories/markers or recursively remove any directory.

The persistent inventory must itself be bound to its created filesystem object.
A copied valid inventory must not grant deletion of the copy or ownership at a
new destination. Allocate its exclusive scratch inode first, capture stable
identity (device/inode/birth/owner/group/mode/link count), then seal a payload
containing that identity, the opened assets-directory identity, exact parent/leaf
binding, committed primary digest, required-resource names and owned receipts.
Validate HMAC before decoding authority-bearing payload fields, then verify the
self/directory binding against opened objects. Byte-identical copies with a new
inode/parent are preserved, not adopted. Compare primary leaf/directory strings
by UTF-8 bytes where normalization could conflate distinct names.

Extend ExportJournalStore with a narrowly typed companion sealing/verification
facade under its existing producer lock. Keep the key private and use distinct
version/domain separators for companion pending and committed records. An
AuthenticatedCompanion capability can mint usable receipts only after full
binding validation; an archived model by itself cannot. Resource receipts retain
inode/birth/type/size/digest/owner/mode/link/flags checks. Rebinding a legitimate
rename's change-time is allowed only after inspecting the same authenticated
object and bytes; never accept another inode or modified content.

## Records and bounded storage

Use a single fixed inventory name, `.mostlytext-export-inventory.json`, in the
already primary-bound assets directory. New private pending state uses the same
parent/leaf hash plus a separate companion suffix, under the existing private
0700 producer directory. Retire successful private checkpoints so explicitly
chosen output basenames do not create a new private lifetime-output quota.

Pending state records operation ID, prior/desired primary digests, asset-directory
identity, previous authenticated state, desired resource identities, exclusively
created stage/receipt transitions, metadata-swap stage and recorded quarantines.
Persist each retirement/quarantine name BEFORE its mutation. Validate exact names,
resource/digest correspondence, duplicate entries, schema and all array bounds.

Keep primary-journal 64 KiB, public resource counts/payload/final-HTML budgets,
source limits and existing injected resource ceilings unchanged. Companion control
payloads are capped at 512 KiB, their encoded envelopes at 1 MiB, and aggregate
private control storage at 64 MiB. Bound up to two resource generations in pending
metadata; published obsolete entries shrink after verified retirement. Exhaustion
blocks growth and preserves data. A verified inventory has a separate fixed
control-file allowance; unknown files still consume the existing retained-file/
byte quota. Do not silently raise resource budgets to fit a transition. A
saturated output may need a different basename; previous usable assets are kept.

## State and publication order

1. Under the existing opened-parent directory gate and producer lock, reconcile
   primary staging, then companion pending state, against the actual primary
   digest. Unknown primary/directory/object state disables destructive recovery.
2. Create the primary scratch and durable primary receipt using the existing
   mechanism. Preserve its current conservative pre-receipt crash gap. Before
   any companion mutation, persist the companion intent and known previous state.
3. Pin/admit the managed directory. Record a newly created directory's identity
   before marker/resources. A crash before that receipt leaves an unfamiliar
   directory preserved and reported; do not infer ownership from an empty name.
4. For each missing resource, record its intended exclusive temporary name,
   write/fsync it, record its exact receipt, and promote with RENAME_EXCL to the
   content-addressed name. Prefer exclusive rename over a new hard-link
   transition. If another final name appears, verify reusable bytes but do not
   adopt ownership; retire only the recorded own scratch. Persist promotion so
   recovery can recognise either the recorded stage or final inode.
5. Verify all required resources, pinned directory, admission/protected objects
   and lease, then perform the existing atomic primary promotion. Cancellation
   before this cutoff prevents it; cancellation after success cannot fabricate
   rollback or turn a saved export into a precommit failure.
6. Write/fsync a self-bound authenticated inventory for the observed committed
   primary. Replacing prior metadata uses a recorded exclusive stage and atomic
   swap. Verify the displaced old object before retiring it. A raced unknown
   object is preserved at its recorded path; restore without overwriting when
   possible, otherwise retain both and report recovery required. Never overwrite
   or unlink unverified metadata merely because its name is reserved.
7. Only when the real primary equals the recorded desired digest and the
   required-resource reference set is known, retire obsolete owned resources.
   Record a unique no-replace quarantine name first, move, then verify the
   quarantined inode/metadata/hash before removal. Recheck directory/primary and
   live-document protection at mutation boundaries. Restore without replacement
   on mismatch; if restoration collides, preserve both and report precise paths.
8. Checkpoint the reduced inventory, sync and retire private pending state.
   Failure after primary promotion is a precise nonfatal recovery warning;
   preserve the saved output and pending receipts for the next explicit retry.

A crash before a receipt is durable cannot grant authority retroactively. Preserve
unrecorded/partial files and refuse further growth when ambiguous. Do not search
for and adopt names by pattern. Tests must state those conservative gaps rather
than promise recovery of every machine-instruction or physical-power-loss window.

## Abort, old state and mode switching

If the actual primary matches the prior digest, retain prior required resources.
Only newly owned files proved irrelevant to a known prior reference set may be
retired. A legacy/unknown prior reference set cannot justify deletion: preserve
and carry known ownership conservatively until a later known primary commit.
An absent prior primary has a known empty reference set. Missing owned files can
be dropped without deleting anything; changed/foreign objects remain preserved.

Self-contained HTML creates no new companion directory. If a valid managed
inventory already exists, advance its primary digest while retaining its assets;
unknown sidecars are left untouched. Later companion output reconciles known
retained assets. PDF uses its existing separate primary output and does not
recursively remove sibling assets. Different explicit basenames remain separate
user outputs. No unowned or currently adopted editor file is cleanup material.

## Implementation units and proof

A. Prove the bounded self-bound manifest/HMAC/receipt model on actual owned files:
   copied/replaced inode, wrong parent/leaf/key/domain/schema, corrupt/oversized
   payload, duplicate/path-traversal entries, nonregular/hardlinked objects and
   changed bytes must fail. No public model may mint deletion authority.
B. Implement pending/resource/metadata-swap and recorded retirement transitions;
   inject interruptions before/after every persisted step and verify retained
   bytes, existing-primary readability, exact-once recovery and quota behavior.
C. Integrate only the authenticated production writer path, preserving the
   no-recovery path and every existing admission/lease/alias/collision guard.
   Include self-contained/linked/embedded mode switching and real resource files.
D. Execute 100 alternating changed exports with controlled crash phases; test
   unknown user files, modified resources, legacy directories, symlinks/FIFOs,
   replaced directories/markers/inventories, restore collisions, disk/write
   failures, protected source/adopted working files, multiple windows and maximum
   record/quota boundaries. Run source-equivalent Debug/Release fixtures, relevant
   and full hosted tests, strict formatting/lint/Compliance, and locked compile-
   only Release. Retain failing-before controls and exact source hashes.

Do not merge an unused record scaffold or check the original #11 criterion until
actual production-path recovery and the adversarial/100-cycle proof pass. Native
HTML/PDF UI, renderer calibration, signed artifact and complete #11/#17 remain
in their separate original rows. Stop for a narrow architecture correction if
any necessary ownership/persistence invariant cannot be met; do not bypass the
proof with deletion by pattern, weakened checks or fabricated native evidence.

## Reference-closure correction before publication integration

Unit A's independent ownership review exposed a false assumption: the generated
resource manifest is not necessarily the complete set of assets referenced by
ordinary exported HTML. Preserved authored raw HTML, local navigation links,
unresolved images, custom derived HTML or caller-supplied CSS can refer to an old
managed file without registering a generated resource slot. Deleting that file
merely because it is absent from the generated list would break the new output.

Add producer-certified reference knowledge to the prepared/publication snapshot.
Public/manual prepared values default to unknown; outside callers cannot assert
closed references through a new public flag. Only the existing ExportComposer
may certify its own generated shell/CSS/body after observing no authored raw
HTML, no custom derived contributions, no unresolved kept images and no
untracked local navigation references. Reuse ExportURLPolicy/actual emitter
callbacks rather than inventing a second URL parser or adding a sanitizer.
Fragment-only navigation is local to the document; conservative uncertainty is
acceptable. Bind this fact into ordinary and optional publication inputs and
snapshots; a source/hash mismatch must not inherit certification.

A pending operation always records required newly prepared resource names for
staging/verification. Its committed inventory uses referencesKnown=false and an
empty requiredNames list when closure is unknown; owned receipts remain retained
and are not mistaken for a complete reference set. No obsolete-resource cleanup
runs for unknown closure. Known producer temporary/metadata retirement remains
permitted with exact receipts and live-document protection. Self-contained mode
continues to retain old assets. A later certified closed primary may retire only
its proven obsolete owned resources. This preserves current conservative behavior
for ambiguous output; quotas still block growth instead of deleting unknown data.

Add real composer/emitter regressions for a literal authored old-assets href,
raw HTML/resource attributes, unresolved images, custom contributions and
manually supplied prepared values/CSS, alongside positive closed Markdown cases.
The 100-cycle crash proof must include both eligible cleanup and ineligible
retention/backpressure. This correction changes no budget, authored text, raw-
HTML policy, dependency or native gate. Complete it before activating cleanup;
Unit A's authenticated model alone remains deliberately unmerged scaffolding.

## Commit and retirement cutoff

Before the first irreversible obsolete-resource retirement, persist the pending
operation's committed phase. After this point a primary whose bytes revert to
the prior digest is an external post-commit modification, not an aborted export.
Refuse further cleanup; never reinterpret that state as rollback, because assets
needed by the former primary may already have been retired. This phase must
survive restart and is checked alongside the actual primary before mutation.

The same rule applies to abort cleanup: persist an explicit aborted phase before
retiring newly installed files against the known prior reference set. Thereafter
only the prior primary state is admissible. If an external writer later restores
the desired bytes, refuse further cleanup rather than interpreting that as a
late commit after abort has already retired resources. Metadata installation is
bound to the selected committed/aborted phase as well as the observed digest.

The reference certificate also requires the exact already-reviewed structural
CSS identity used by the existing optional SVG head audit. Share that fixed
identity within ExportService; ordinary export must conservatively lose cleanup
eligibility if bundled CSS changes before renewed reference review. Color-only
variables remain generated from Theme values. This adds no parser, sanitizer,
style rewrite or dependency, and does not enable optional SVG publication.

## Resource-content reference correction

A packaged authored SVG can itself contain relative references to older managed
files. Its generated outer img URL is not proof that the resource's contents are
closed. Do not add a recursive reader or rely on browser image-mode restrictions.
Only the existing inline-raster allowlist (PNG/JPEG/GIF/WebP) may preserve a
reference certificate when packaged; other accepted image MIME types continue
to export normally but make cleanup ineligible. Reuse ExportURLPolicy's existing
raster media knowledge. Add a real composed SVG/older-managed-PNG preservation
regression. This changes cleanup authority only, not accepted content or output.
