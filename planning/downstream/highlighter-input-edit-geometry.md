# Complete the explicit InputEdit geometry contract

MostlyText #19's original geometry row requires start/old-end/new-end InputEdit
assertions across empty, single-line, Unicode, newline relocation and whole
replacement. The corrected byte-column transformer and prior mounted parser-node
proof are already integrated. The current tests do not explicitly cover the
actual pinned Neon InputEdit constructor across that full matrix.

Add a focused contract test calling that real constructor with the real host
transformer. Save the old endpoint before editing, then update source/revision and
construct the edit as Neon does. Assert independently specified UTF-16 byte/Point
coordinates for all three endpoints. Prime the line cache first so same-length
newline relocation exercises invalidation. Do not copy or replace the constructor,
modify production geometry, patch a checkout or update any dependency.

Baseline: stacked on PR #42 source 3b6afb39, retaining PR #41. Architecture is
committed before tests. A compile error from an inaccessible dependency-internal
initializer must be resolved without exposing a new production API or testing a
copy of the constructor. If access requires a dependency patch, stop this test
unit for a focused contract revision rather than broaden the fork.

Verify strict formatting/lint, compile-only test build as useful, complete hosted
package/app CI and Compliance on the exact source. No local product/AppKit test
execution. Preserve all current native/reproduction gates: the original mounted
Debug abort, stale completion/lifecycle/IME stress and full-size Release budget
are not proved by these geometry assertions or an unrelated full suite. Only the
explicit geometry criterion may be reconciled after real hosted execution.
