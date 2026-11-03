# Bound embedded CLI application metadata reads

## Owner outcome and baseline

The public mostlytext CLI must refuse malformed application metadata promptly,
without following an Info.plist symlink or blocking on a FIFO. Keep the actual
embedded-tool/container lookup and signed cold-launch policy. Baseline d18ca0f3
stacks the export work; master stays 15c0fae2. This is a narrow #18/#183 review
remediation; it does not need Daybreak, an installed app or another account.

## Source-confirmed gap and binding change

EmbeddedCommandApplication.locate bounds bytes only after FileHandle opens the
Info.plist pathname. That open follows a leaf symlink and can block on a FIFO
before a deadline or size check. Extract only metadata I/O and the shared failure
enum to a Foundation/Darwin source file. Use nonblocking, no-follow, close-on-exec
read-only open; require a regular file of at most 64 KiB before allocation. Read
bounded chunks with EINTR handling and a one-byte growth probe. Check descriptor
and no-follow named identities, size, modification/change times and final byte
count before returning immutable bytes. Existing property-list identity parsing,
app/main executable resolution, signature verification, argument parsing,
transport and launch behavior stay in their current owners.

A private post-open test hook drives real replacement/in-place mutation; it is
not exposed by the public CLI. No fallback path read or unsigned launch override.
The helper is read-only and creates/deletes no user objects.

## Proof and limits

A source-identical non-application harness executes only the Foundation/POSIX
helper against private files: exact 0/1/64-KiB boundaries, oversized data, FIFO,
directory/missing paths, symlink, post-open replacement and in-place mutation,
and descriptor cleanup. Replacing it with the prior path-following read must
fail the symlink assertion. Hosted tests also call the public locator against
the malformed bundle. Strict lint/pinned format, Compliance, unsigned compile-only
app/UI targets and complete exact-head hosted CI remain required. This does not
claim arbitrary same-UID writer exclusion, signed installed CLI acceptance or
native application launch; no app/local app-target execution occurs.
