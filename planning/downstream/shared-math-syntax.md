# Share original-source math delimiters without changing production paths yet

## Owner outcome and scope

Preview and Export need one deliberate delimiter grammar that preserves currency,
escapes and original source coordinates. Implement the Foundation-only MathSyntax
package specified by issue-116-handoff.md, now that the actual Textual attachment
probe in PR82 has passed full hosted validation and merged. This is its grammar/
value foundation; do not switch either production math path independently.

Current merged baseline30d7692f3a535c0e8930a3b80ec2f2af92727e28 includes the
qualified attachment factory, parser/client/buffer repairs and lexer lookup.
The independent one-phase style-result correction is being prepared separately;
preserve its eventual pin when reconciling main. No third-party dependency or
existing package pin changes in this foundation slice.

## Ownership, values and fixed policy

MathSyntax imports Foundation only and owns immutable Sendable source identity,
inline/display style, full/body UTF-16 ranges and unchanged expression text.
The caller supplies an opaque immutable-source UUID tied to its document,
lifetime and content generation. The lexer does not create navigation authority,
validate document lifetime or use that identity as a renderer-cache key.

The caller also supplies nonoverlapping original-source regions from structural
admission and literal exclusion ranges. Regions stay separate even when adjacent;
no delimiter can cross a region or an excluded span. Reject out-of-bounds,
overlapping-region or surrogate-splitting metadata. Merge overlapping exclusions.
Do not parse Markdown structure here or adopt the editor's approximate fence
classifier. Math owns authoritative AST admission and container-prefix mapping in
the next integration; this package preserves the raw body including all newlines.

Require an explicit nonnegative maximum span count. Return a literal-remainder
offset if work stops at that cap. The consumer must keep that tail authored text
and disable Textual's hidden second math pass. This package chooses no product
count/document-size policy; reconcile the current256-span preview cap and100-
equation performance corpus in the owning analysis rather than conflating them.

V1 scans UTF-16/scalars, not Character or repeated suffix regexes. Odd complete
backslash runs escape a dollar; even runs do not. Display $$ takes precedence and
requires a nonempty body, preserving single newlines/TeX comments and never
crossing a blank line (LF/CRLF/CR plus horizontal whitespace). Inline requires a
non-whitespace opener/body end, never crosses CR/LF and cannot close immediately
before a Unicode decimal digit. Explicit $5$ is math; $x$2 stays literal.
An invalid inline closer abandons that candidate and is reconsidered as an
opener, preserving later $x$ in "$5 and $10; then $x$".

Define unmatched display recovery explicitly: an unpaired $$ remains literal,
consume both delimiter characters, then continue looking for later independent
math. Do not reinterpret its second dollar as an inline opener. This deliberate
clarification differs from the old regex fallback and must be tested before any
production activation. Overlapping double-dollar starts are indexed so a
nonempty body can still be the single dollar in $$$$$, matching closest valid
closure. These ambiguous cases are fixture policy, not renderer validation.

## Algorithm, resources and execution

Build one original UTF-16 buffer. Validate/sort regions and exclusions, split
regions at exclusions with a monotonic sweep, then scan each segment. Index
unescaped double-dollar starts and blank-line generations once. Two monotonic
indices find the next nonempty same-generation display close; the main cursor
never rescans a suffix. Inline recovery advances without rewinding. Complexity
is O(N + R log R + E log E), with linear buffer/index storage and output bounded
by the explicit span limit. Check cancellation before allocation, periodically
and before returning; no renderer, process, filesystem or network capability.

Standalone Debug/Release Swift Testing covers exact ranges/body bytes, currency,
odd/even escapes, malformed/unpaired recovery, dollar runs, all line endings,
Unicode whitespace/digits/emoji/combining/Prepend scalars, region/literal barriers,
invalid metadata, caps and cancellation. Include a large adversarial dollar run
under an unchanged one-minute watchdog; do not claim complete-editor performance.
CI must execute this separate package explicitly because dependency test targets
do not run with MacDownKit. Register its manifest/inventory, then full package/
app/CLI checks and exact-head review. No local native product execution.

## Integration and residual gates

Keep existing MathSpanScanner, MathContribution and Preview's parser/preprocessor
unchanged until shared structural analysis and the tested native transport consume
this package together. Future adapters must compare actual Preview/Export results
against the same expected source tokens, remove the lossy newline/marker paths,
expose structured engine outcomes, bound actual renderer work and bind accessible
navigation to live document identity. Pure grammar tests do not close issue9,
final visual/VoiceOver, release or exact-artifact acceptance. Reassess all open
issues after each actual checklist/comment update.

## Predecessor reconciliation

Include ready PR83 exacthead22a7b539ae2c74d8c23880d4c07eeed4deb34347 before
publication, preserving Neoncd14f22a alongside the qualified Textual factory.
The app manifest and all24 existing pins are byte-identical to that predecessor;
this package adds no remote dependency and does not switch production consumers.
Combined inventory/316Compliance/fullformat/strictlint pass. PR83 must complete
its full CI and merge before this unit; reconcile actual main's resulting tree
without resetting any newer source or pin. The current foundation tests pass19
functions/two suites Debug/Release.
