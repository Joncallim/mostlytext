# One command exchange over a verified connection

## Owner summary

Send one CLI request and optional exact stdin bytes, then report acceptance or
wait for actual completion through the existing validated reply stream. A lost
connection is an error, never proof that documents closed or permission to
relaunch/replay. This unit makes the connected client usable without starting
the app or changing public command syntax.

Baseline: master `15c0fae22f7618e94c82681227057c66011be2a9`, integration
`fdee161354050d19cbb91736eea04de9786b7bbc`, stacked with PRs #554 and #555.
The shared request/framing/stdin/reply codecs, peer-checked connection and
instance-bound endpoint handshake already exist. Reuse them rather than add
another protocol or lifetime owner.

## Ownership and bounds

`CommandClientExchange` runs synchronously under one off-main owner. Its caller
hands over a connected socket obtained through the verified endpoint client;
the exchange closes that connection on every return or throw. It opens no
endpoint, launches no process and has no retry/reconnect path. Request values
and the optional stdin Data are immutable. Nil stdin differs from an empty
stream. Validate declared length, SHA-256 and strict UTF-8 before sending any
request bytes, preserving BOM/line endings and nonzero Data indices. Check
cancellation and both deadlines before and after that bounded validation.

Encode metadata through the existing strict codec and stream stdin in chunks
no larger than 64 KiB, followed by the explicit empty terminator only when stdin
was declared. Reuse the 32 MiB body and existing path/metadata limits. Retain one
temporary chunk/frame; never construct a second whole framed body. The caller
still owns bounded acquisition of stdin before this operation.

Use finite monotonic input and acceptance deadlines. Only after a valid waiting
acceptance does the next read omit its editing deadline; 50 ms cancellation
polling remains active. Feed all replies through the request-bound reducer.
Premature EOF, wrong request IDs, impossible ordering/counts, malformed replies,
timeout and cancellation throw and close. Return only a finished result with
opened count/partial failures or a typed rejection. No result claims saved files.

This API has no shared mutable state, background workers, user diagnostics,
filesystem/document grants or new dependencies. Application admission, public
argument-parser/embedded-app locator, activation and real document lifetime
integration remain separate. No native acceptance follows from socket controls.

## Verification

Use disposable Unix socket pairs and worker-owned peer connections. Inspect
exact metadata, multi-chunk/BOM/empty stdin and explicit terminators; reject
undeclared/mismatched/malformed stdin before any request; verify non-wait,
wait-past-acceptance-deadline, partial failure/rejection, close-before-ack,
wrong/duplicate/finished-first replies, finite input/ack timeouts and cancellation
during wait. Verify connection closure in success and failure paths. Run combined
Debug/Release tests, strict lint/format, Compliance and full hosted CI, then
self-review before integration. No app or real preference domain is needed.

## Local verification

All 214 combined CommandBridge/AppSettings tests in 28 suites pass in Debug and
Release with source hashes bound to the copied Foundation-only harness. The
exchange adds 11 test functions, including the parameterized stdin corpus.
Strict lint/format and ordinary Compliance pass. Initial test compilation found
a throwing-expression macro inference issue; explicit throwing reads resolved
it. A first concurrent run then exposed test-peer starvation on the shared
cooperative pool. Dedicated fixture-owned threads remove that starvation without
serializing or weakening production tests. Initial failures and corrected logs
remain under `CORTANA-Builds/command-client-exchange-20261101`. Full hosted CI is
required before merge; no public CLI/application or native lifetime journey ran.
