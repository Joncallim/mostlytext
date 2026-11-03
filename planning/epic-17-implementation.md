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

Reservations bind an opaque ledger-instance token, a fresh per-reservation UUID
and canonical request digest. Same-entry replay retains its reservation token;
after expiry, reusing a request UUID creates a distinct token, so an obsolete
reservation cannot bind or reject the replacement request.
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
17 suites. After final formatting, all 50 CommandBridge tests passed with
unchanged source hashes. Receipts and logs are retained in
`CORTANA-Builds/resume-20261101-command-replies`; source compliance, formatting
and strict lint pass. These are package controls, not CLI/app acceptance.

## Private endpoint ownership before listener activation

CommandEndpointLocation derives a short per-product directory from SHA-256 of
the exact product identity under a caller-supplied OS per-user runtime directory.
It validates absolute file URLs, path components and sockaddr_un capacity before
creating anything. CommandEndpointLease walks directories with no-follow file
descriptors, requires the runtime and endpoint directories to be owned by the
effective user with mode 0700, rejects allow ACLs and noowners filesystems, and
holds an exclusive nonblocking advisory lock on an owned regular 0600 file.

Never unlink a lock or endpoint on a failed acquisition. Compare the named
directory and lock inode/device to the held descriptors before later activation;
replacement is an error, not permission to delete a path. Release closes only
owned descriptors. A separate peer check uses the kernel's Unix-socket peer UID
in both future transport directions. This isolates other users; it is not
authentication against hostile code running as the same user.

This unit creates no listener, accepts no requests and removes no stale socket.
Subsequent listener/client code must consume the lease, recheck its identities
before bind/connect, set/verify 0600 socket permissions and implement the full
bounded deadlines and stale-instance handshake contract. Tests use newly created
private internal-disk directories and Unix socket pairs only. Verify contention,
release/reacquisition, modes, symlinks, hard links, path replacement, long paths,
ACL refusal and peer checks without starting an application.

Endpoint-unit verification: all 62 CommandBridge tests pass with unchanged
source hashes, and the CommandBridge target builds in Release. The expanded
control caught Foundation reintroducing the `/var` alias into the OS temporary
path; the resolver now uses POSIX realpath before no-follow traversal. The
failing and corrected runs remain in
`CORTANA-Builds/resume-20261101-command-replies`, with
`receipt-endpoint-corrected.json` recording the final tests/build. Formatting,
strict lint and ordinary source compliance pass. No cross-user GUI or native
CLI/app claim follows from same-user socket-pair controls.

## Connected-socket I/O unit

CommandSocketConnection takes exclusive ownership of an already connected Unix
stream descriptor, verifies its kernel peer, sets nonblocking/close-on-exec and
per-send SIGPIPE protection, then supplies framed reads/writes. It has one
serialized off-main owner and is not Sendable. It creates/connects/listens on no
endpoint. Read one frame at a time through the shared decoder and retain at most
one 4 KiB unread chunk; writes retain one bounded encoded frame. Partial I/O,
EINTR and EAGAIN are handled without treating them as message boundaries.

Handshake/input/ack callers supply finite monotonic deadlines. Only the eventual
client document-wait phase may omit its deadline. Poll in at most 50 ms slices
to observe cancellation without a helper thread. Clean EOF is distinct from an
empty frame; a partial frame at EOF is an error. Timeout, cancellation, malformed
input and system errors close the owned descriptor and clear held bytes. They
never report document completion or remove a receipt/document. Transport callers
still reserve capacity before reading and drain their actual admission workers.

Use socket-pair controls for coalesced/empty frames, partial EOF, oversized
headers, exact outgoing bytes, deadlines, cancellation and peer-closed writes.
No network endpoint or application is started for this unit.

Connected-I/O verification: all 71 CommandBridge tests in nine suites pass with
unchanged source hashes, including real socket backpressure and partial-input
timeout controls. The CommandBridge target builds in Release. Formatting, strict
lint and source compliance pass. The exact commands and manifests are in
`CORTANA-Builds/resume-20261101-command-replies/receipt-socket-io-final.json`.
Endpoint listener/connect ownership, stale-endpoint handshake, request admission
workers and native CLI/application journeys remain subsequent units.

## Endpoint transport and instance identity

Baseline for this unit: integration `fdee161354050d19cbb91736eea04de9786b7bbc`,
master `15c0fae22f7618e94c82681227057c66011be2a9`. Deliver a usable private
listener/client boundary without activating an application listener at startup.
No signing, test account, ordinary app or real preference domain is required.

CommandEndpointListener exclusively owns its lease and listening descriptor.
Before binding, validate the held namespace and any existing socket's owner,
type, mode, link count and ACL. A held competing lease always wins. If an
unleased existing socket accepts a connection, preserve it as possibly live.
Only a definite kernel ECONNREFUSED under the exclusive lease permits stale
retirement; timeout, cancellation, unknown errors and protocol incompatibility
never authorize deletion. Recheck namespace and exact device/inode/birth identity
before retirement. Rename the object to an unpredictable quarantine name without
replacement, verify the moved object, then remove only that same owned socket.
Preserve/restore unexpected objects without overwriting a newer path. Never
unlink a lock or directory. This isolates other users, not hostile same-UID code.

Bind before listen, set/verify 0600 and close-on-exec/nonblocking flags, and keep
the parent 0700 ownership checks. The backlog is eight; this is not a claim that
application admission slots/bytes have been reserved. Accept one peer at a time
under a finite monotonic deadline. Both directions verify kernel peer UID.
Connection ownership transfers exactly once, including constructor failures.

Each listener lifetime has one random instance UUID. On accept, write a bounded
version-1 `hello` frame with that UUID. Client connection validates exact fields,
types/version and UUID before returning the existing framed connection plus
instance identity. A caller-supplied expected instance must match on reconnect;
otherwise close and report instanceChanged, with no replay, relaunch or retry.
The hello is compatibility/instance data, not same-UID application authentication.
Use the existing strict JSON admission and frame caps. Poll at most 50 ms for
cancellation; public connect and accept/hello consume the caller's finite
deadline. The application server's internal idle/greeting phases are separately
bounded as amended in
`downstream/cli-idle-and-hello-budgets-2026-11-03.md`; its idle polling deadline
must not truncate a newly admitted peer's greeting.

Allow changes in CommandBridge endpoint/polling/hello code and its tests only.
Keep classes non-Sendable with one serialized off-main owner. Tests exercise real
private pathname sockets, hello/frame exchange, live/unleased/refused endpoints,
contenders, replacement/symlink/hard-link/ACL/mode refusal, bounded timeout and
cancellation, instance changes, repeated close and retention of foreign objects.
Run focused Debug/Release controls, full hosted regression/build/lint/compliance,
then source review before merge. Application worker admission, CLI arguments,
bootstrap and native document-lifetime journeys remain later E17 integration.

Endpoint transport controls: 87 CommandBridge tests in ten suites pass in both
Debug and Release in the dependency-free Foundation/Darwin harness. This includes
real pathname hello/frame exchange, refused/live/leased endpoints, socket ACLs,
namespace replacement and a deterministic replace-before-quarantine control.
Source review added an accepted-peer identity recheck after polling, with a
regression that changes the path during that wait and proves closure before any
hello. Strict lint/format and ordinary Compliance pass. Initial expanded-test
compilation errors (Duration negation and a nested throwing #require expression)
and the test-file type-length correction remain in the retained logs under
`CORTANA-Builds/command-transport-20261101`. Full hosted execution is required
before integration; no public CLI/application or cross-user GUI journey ran.

A combined optimized test run subsequently exposed a fast-peer-disconnect race:
Darwin can reject setting SO_NOSIGPIPE with EINVAL after the peer has already
closed. Writes now use MSG_NOSIGNAL on every send, as supported by the macOS SDK,
so initialization can retain buffered final bytes without relying on a late
socket-option mutation. A closed-before-adoption regression reads those bytes
and verifies that the subsequent write throws without SIGPIPE. All 88 transport
tests pass in Debug and Release; the failing combined run and instrumented
reproduction are retained rather than retried away.
An optimized diagnostic harness also completes 2,000 repeated timeout/cancel/
reconnect exchanges with the corrected source. This is a stress control for the
observed disconnect race, not a replacement for full hosted or native acceptance.

## Embedded CLI metadata read boundary — 3 November 2026

The enclosing-app locator now reads Info.plist through the Foundation/POSIX
`CommandApplicationMetadata` helper: nonblocking/no-follow regular-file open,
64-KiB pre-allocation limit, bounded chunks/growth probe, and descriptor/named
identity plus size/time checks before returning immutable bytes. A FIFO cannot
block the ordinary path-following FileHandle open, and a leaf symlink cannot
supply external metadata. App/signature/launch policy is unchanged; no installed
application or signed launch is exercised by local controls. The binding source
unit, real-file tests and limits are in `downstream/bounded-cli-metadata.md`.
This is source hardening for #18/#183, not installed CLI or signed native
acceptance. Local app/UI targets compile only; full hosted checks remain required.
