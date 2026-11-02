# App command admission and document lifetime

## Owner summary

Connect the public command to the existing app file-opening path after launch
restoration. A verified request opens or focuses ordinary document windows;
--wait follows those logical document windows through Save As until confirmed
close. Parsing, hashing, socket I/O and editing waits remain off MainActor.
MainActor owns receipt bindings beside the window transaction, so a close before
acceptance cannot be lost. Replay subscribes to the original result and does not
open again. No owner-account app launch is part of implementation verification.

Baseline: integration fc3689cd, stacked #558/#559. This change admits file paths
and activation. Valid stdin requests are explicitly refused by the production
handler before opening any files, until a dirty untitled document has both
verified recovery and a durable restoration reference before acknowledgement.
A recovery file alone is insufficient. Production migration consent/global
bootstrap and native acceptance remain separate open #18/#53 gates.

## Ownership and bounds

A dedicated listener thread owns its private endpoint lease. At most 128
connection workers use dedicated threads; at most eight requests and 64 MiB of
aggregate declared stdin are admitted before body buffering. A single-use Mutex
transfers each non-Sendable socket to exactly one worker; no concurrent read,
write or close. Input capacity is retained through an asynchronous MainActor
admission even if the client times out. Immutable validated request/input values
cross to MainActor, which owns the existing receipt ledger. Event mailboxes
avoid continuous MainActor polling. A client disconnect removes only its own
subscription; it neither replays nor cancels another subscriber's documents.

Every input/handshake/acceptance/write operation has a monotonic deadline.
Only a valid accepted --wait request may wait without an editing deadline.
Malformed/truncated/hash-mismatched input reaches no app callback. Snapshot
notifications report accepted before finished even if close preceded acceptance.
Successful Quit closes logical lifetimes only after verified session persistence;
a cancelled Quit preserves subscriptions. Shutdown is bounded and does not unlink
replacement endpoint objects. Endpoint creation is disabled in UI/app test hosts.

## App transaction

An optional admission callback enters the ordinary keyed open pipeline. For an
existing live controller it binds synchronously before focus; for a new controller
it binds immediately before addition/show with no suspension between binding and
exposure. Confirmed controller retirement closes its stable logical UUID; Save As
and recovery epochs do not change that UUID. Activation binds the focused live
window, creating one through the ordinary reopen path if required.

The service starts only once the ordinary launch/unsaved restoration has settled;
first-run UI must finish before it starts. Failure to own the endpoint leaves
ordinary app use available and CLI unavailable. No configurable client-provided
socket path, protocol bypass, unsigned launch switch or second file-open path.

## Verification

Synthetic end-to-end tests exercise real private sockets, exact input, replay,
partial opens, duplicate aliases, close-before-acceptance, independent subscribers,
disconnect, stalled/truncated/invalid input and capacity release. Pure receiver
controls exercise delayed admission/cancellation and logical lifetime ownership.
App adapter controls run in hosted serial app tests; local tests never launch
AppDelegate or access real preferences/recovery/session paths. Full locked hosted
Debug/Release builds and suites are required before merge. Native open/focus/close,
Save As and clean Quit acceptance remain unverified until a suitable GUI account.

## Verification update

The combined isolated transport controls pass 108 tests in 13 suites in both
Debug and Release without warnings. A suspected link/../ path bug was not
reproduced: macOS Foundation's existing final-symlink resolution already opens
the physical parent target. Retain that passing filesystem regression without
changing the production path helper. Dedicated-thread fixture close tasks are
cancelled on failure to avoid orphaned asynchronous test work.
