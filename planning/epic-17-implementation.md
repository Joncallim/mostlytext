# MostlyText installation, command line and update implementation

## Owner summary

Deliver the already-promised MostlyText installation and command-line journeys
without losing development state or opening an unauthenticated network service.
The accepted downstream #18 architecture and RELEASE_SEQUENCE remain binding.
This first executable unit supplies bounded immutable CLI request values and
stream admission; it does not activate a socket, launch an app or change release
identity, preferences, signing, updater configuration or public distribution.

## Baseline and reconciliation

Live master is `15c0fae22f7618e94c82681227057c66011be2a9`; engineering integration
is `9de81f5ff5222138a210472f2def33de01df6c8c`, inspected 1 November 2026.
The CLI currently only lists registry formats and otherwise prints a placeholder.
Its separate MacDown2CLI scheme is now fixed. Existing FileCore decoding and
window/document lifetime owners will be reused by later application integration.
No CLI transport/replay implementation exists to reuse. #53 admission and E23
custom-theme work are separate drafts; bootstrap must consume their final APIs.
#88 still holds local app/native execution until an isolated GUI is proven.

## Journeys and invariants

The final CLI opens explicit paths, accepts strict UTF-8 stdin, activates an
existing app and waits for logical document closure when requested. Paths remain
structured data, including spaces, newlines, Unicode and shell metacharacters.
Resolve relative spellings against the captured caller directory by joining;
do not lexically remove `..` across a possible symlink. No implicit file creation,
shell interpolation, parent-folder grant or lossy text conversion is authorized.
An empty stdin stream is distinct from no stdin. Transport retains its exact
bytes, including a UTF-8 BOM and original line endings, for FileCore admission.

## Ownership and first-unit interfaces

Add CommandBridge to MacDownKit with Foundation, CryptoKit and the already-pinned
JSONSupport target. It owns Sendable immutable CommandOpenRequest and
CommandStdinDescriptor values, CommandRequestCodec, CommandFrameDecoder and
CommandStdinAccumulator. It imports no AppKit, Workspace or settings module.
The app and CLI will depend on this shared target in later slices.

Metadata is strict UTF-8 JSON with exact protocol version 1, type `open`, UUID,
absolute path strings, wait Boolean and an optional stdin descriptor containing
byte count and lowercase SHA-256. Unknown/duplicate members, null optionals,
noncanonical numeric version/count spellings, malformed UUIDs/digests and NUL
paths fail closed. Canonical sorted encoding determines request fingerprints;
Unicode scalar spellings and stdin digest remain byte-sensitive. A changed
payload under an existing request UUID must never be treated as replay.

Frames use a four-byte unsigned big-endian length prefix and at most 64 KiB of
payload. consume accepts at most one frame and reports the exact input count
consumed, so concatenated input never creates an unbounded completed-frame
queue. Inspect the complete header before allocating payload storage. Failure
poisons a decoder; EOF at a partial frame is an error. Cancellation releases
held bytes. Stdin follows metadata as bounded binary frames; an empty frame
explicitly terminates it. Match the declared byte count, SHA-256 and strict
UTF-8 before returning exact bytes. Reserve bytes/slots before socket reads in
the later transport; this reducer does not imply a network admission policy.

## Budgets, state, concurrency and failure

Limits are 64 KiB metadata/chunks, 32 paths, 4096 UTF-8 bytes per path, and 32 MiB
stdin per request. No body allocation follows an oversized header. Decoder-held
memory is one admitted frame plus its four-byte header; stdin retains at most
the admitted payload and bounded temporary validation storage. Values/reducers
have one owning task and no background workers. Parsing, hashing and stdin
validation run off MainActor in the future transport. Partial reads/writes,
EINTR, deadlines, peer checks and cancellation drainage belong to that transport.

Malformed metadata, invalid paths, oversized frames, truncated streams,
count/digest mismatches and invalid UTF-8 return typed failures. After an error,
release bytes and require a fresh connection/decoder rather than resynchronizing
through arbitrary bytes. No request reaches document/recovery APIs in this unit.

## Execution slices and stop conditions

1. Implement strict metadata, framing, stdin and byte-sensitive fingerprints.
   Verify split headers/payloads, concatenation, zero frames, oversized lengths,
   hostile JSON/types, nonzero Data indices, exact Unicode, replay fingerprints,
   all stdin termination failures and boundary sizes in Swift Testing. Run locked
   package checks and an optimized standalone source control without app startup.
2. Add bounded receipt/subscription state, then peer-checked Unix socket transport
   with exclusive instance ownership and safe stale-endpoint handling, using the
   downstream #18 contract. Write its concrete architecture before coding.
3. Pin argument-parser, integrate verified app location and public CLI entry,
   reserve wait subscriptions within window creation/deduplication transactions,
   then execute cold/warm/open/stdin/close-before-ack/Save As/cancel journeys.
4. Execute bootstrap migration and pinned updater units from the downstream
   contract before software S. Keys/feed inputs block only dependent packaging.

Stop on inferred path authority, source normalization, implicit user-store
writes, unbounded allocation/queueing or changed lifetime ownership. Unit 1 is
complete only with adversarial tests, locked builds, source/pin evidence and a
reviewable draft; it does not complete #18. Native CLI/app, migration, update and
signed release evidence still follows RELEASE_SEQUENCE and the isolated GUI gate.

## Receipt and wait-subscription unit

CommandReceiptLedger is a Sendable value reducer with one serialized owner
(MainActor in the app); it never opens documents or retains document models.
Reserve a request and server-generated connection subscriber before admission.
Record a target-to-logical-lifetime binding before exposing a newly created
window, or synchronously while validating an existing live controller. No await
is permitted between that validation/binding and its owning window operation.
Paths/Save As IDs are not lifetime IDs. Closing an unbound obsolete controller
cannot be repaired by this reducer; native integration must enforce the ordering.

Reservations bind an opaque ledger-instance token and canonical request digest.
Same-UUID/same-payload retry joins the existing receipt; a changed payload fails.
Every requested target (path index, stdin or bare activation) must be bound or
explicitly failed before opening completes. Deduplicated targets may share one
lifetime. Save and Save As make no terminal transition; confirmed close/discard
or safe application termination closes the logical lifetime exactly once.

Snapshots contain a monotonic event prefix: accepted first, then finished only
when every bound lifetime closes for a waiting request. A close before opening
completes is retained and still follows the acceptance event. Rejection is allowed
only before any target was admitted. Each connection serially sends the new
snapshot suffix using its own event cursor; reconnect/replay starts at zero.
Acknowledging acceptance removes non-wait subscribers; waiting subscribers stay
until terminal delivery acknowledgement. Disconnect removes only that connection,
never accepted source or another waiter.

Bound eight preparing requests, 64 MiB total declared stdin, 128 total subscribers
and 512 retained receipts. Preparing reservations release resources only after
actual admission completion/rejection, not merely task cancellation/disconnect.
The transport must reject/drain failed input and workers under finite deadlines.
Receipts with no subscribers may expire after five minutes of inactivity once
preparation completes; active waiters do not expire. Capacity exhaustion refuses
new work rather than evicting an active receipt. The replay guarantee is limited
to one live app instance and retained receipt; clients never blindly retry after
instance loss or expiry. Tests inject a monotonic clock and cover foreign tokens,
changed payloads, duplicate targets, close-before-ack, Save As lifetime stability,
independent waiters, partial failure, actual resource release and bounded expiry.

## Reply admission before transport

The next shared-code unit encodes receipt events and validates their order at
the client. It opens no endpoint or document. Use bounded strict JSON replies
with version 1, type and request UUID. Accepted replies contain openedCount and
failures; finished replies contain no additional members; rejected replies
contain only a stable reason code. Each failure contains a target object and
reason: path targets have kind `path` plus a canonical integer index, while
stdin/activation targets contain only their kind. Human diagnostics remain a
later localized CLI concern, not server-provided free text or source paths.

Reject unknown/duplicate members, wrong types, unsupported versions, invalid
UUIDs/reasons/targets, noncanonical numeric counts, out-of-range counts and
duplicate failed targets. Replies share the 64 KiB frame ceiling. At most 33
targets exist (32 paths plus stdin); activation is the sole bare-request target.

CommandReplyStream binds one immutable original request. An accepted event must
account for valid targets: failures refer only to requested targets, and the
distinct opened lifetime count is positive and no greater than remaining
targets, or zero exactly when all targets failed. A non-wait acceptance is
terminal; a wait acceptance requires a following finished event. Rejection is
terminal only before acceptance. Finished-before-accepted, duplicate acceptance,
wrong UUID, impossible target accounting, data after terminal and EOF before
terminal poison the stream. One fresh stream is required for a deliberate
same-instance reconnect; this reducer never silently retries or relaunches.

Tests cover round trips, malformed replies, byte/count limits, partial failure,
deduplicated documents, activation, request binding, close-before-ack replay
ordering, non-wait acceptance and premature EOF. Keep socket ownership, peer
UID checks, deadlines and resource drainage in the subsequent transport unit.

Reply-unit verification: the locked command-related run passed 75 tests in
17 suites. After final formatting, all 51 CommandBridge tests passed with
unchanged source hashes. Receipts and logs are retained in
`CORTANA-Builds/resume-20261101-command-replies`; source compliance, formatting
and strict lint pass. These are package controls, not CLI/app acceptance.
