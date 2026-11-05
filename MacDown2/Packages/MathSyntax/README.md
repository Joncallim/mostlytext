# Original-source math syntax

MathSyntax supplies immutable source identity, delimiter styles, exact full/body
UTF-16 ranges and unchanged expression text to the shared math analysis. Math
owns parser-derived structural regions, literal exclusions, document lifetime and
rendering policy. Keep adjacent structural regions separate. The tokenizer
validates bounds, overlap and scalar boundaries before scanning.

V1 gives display delimiters precedence, preserves newline/comment bytes, stops
at blank lines, handles complete backslash-run parity and recovers after an
invalid inline closer. Inline edges require non-whitespace and a closer cannot
immediately precede a Unicode decimal digit. `$5$` is explicit math; `$x$2` is
literal; `$5 and $10; then $x$` admits only the last equation. An unmatched `$$`
stays literal as a pair before scanning for later independent math.

Pass a trusted maximum span count explicitly. `literalRemainderOffset` identifies
a tail left unscanned at that limit; retain its authored text and disable any
second math-tokenizer pass. Source snapshot identity belongs to the caller and
must change with original bytes/document lifetime/generation; use a separate
rendering cache identity. Original body bytes and renderer/container-decoded TeX
are separate values.

One UTF-16 buffer, sorted interval sweeps and monotonic delimiter indices bound
work to O(N + R log R + E log E), with linear buffer/index memory and capped
output. Cancellation is checked at entry, periodically and before return. Invoke
the synchronous tokenizer on the owning bounded analysis worker.

Run `swift test --package-path MacDown2/Packages/MathSyntax` from the repository
root, and repeat with `-c release`. CI executes this standalone Foundation-only
package explicitly. The current production MathSpanScanner/Preview/Export paths
remain active until their shared admission/transport integration qualifies;
these package tests alone are not native or release acceptance.
