# Stream move-candidate metadata and verify the opened file identity

## Owner outcome and baseline

Find a renamed document among many unrelated siblings promptly and never
rebind it to replacement bytes that appeared after metadata inspection.
Master is 87d8d48b; the reviewed source baseline is 030a4ff0. Its unchanged move
probe takes 2.07509 seconds in Intel run 41557163319, failing the existing
two-second limit. Preserve that failure and the successful ARM package run.

## Binding scope and authority

The existing code prefetches directory metadata, builds/canonicalizes every URL
and then asks FileManager for a full attributes dictionary for each candidate.
It checks the prior device/inode before snapshotting but does not recheck the
returned snapshot's identity. Add a controlled callback immediately before the
candidate read, reproduce a replacement rebind on that actual old path, then
require the opened snapshot's object ID to equal the prior ID.

Replace array enumeration with one owned POSIX directory stream and relative
no-follow fstatat metadata. Construct a URL/read/hash only for an exact regular
device/inode match. Preserve current-path availability precedence, symlink
refusal, hard-link ambiguity, decoding, parent-error classification and scope.
The opened directory follows the same caller-approved directory path as the
old enumeration; this does not grant a new parent or document root. Close its
descriptor on every path; reset errno around each readdir, and stop remaining
enumeration after cancellation with the same already-found result semantics.

Tests use real owned temporary files, existing 10,000-sibling budget and a
metadata-to-read replacement hook. The old path must fail the replacement
identity assertion. Run exact FileCore sources in Foundation/POSIX Debug and
Release harnesses, then all complete hosted checks. No timing limit is raised.
Device/inode identity is the existing contract, not hostile same-UID atomic
compare-and-swap or a new persistent file-identity scheme. Native monitor/UI
latency and #119 whole acceptance remain separate.

## Focused evidence

The old algorithm with only the declared before-read callback fails two actual
assertions for foreign replacement bytes; its symlink control already refuses
rebinding. The corrected exact-source Foundation/POSIX harness passes all 139
cases in 19 suites in Debug and Release, including the original 10,000-sibling
two-second limit, current-path replacement, backup/ambiguity and both race modes.
No local product, AppKit or UI execution is used as evidence. Complete hosted
qualification and native monitor acceptance remain separate requirements.
