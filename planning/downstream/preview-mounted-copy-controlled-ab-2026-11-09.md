# Private mounted Copy selection A/B

The shipping PR #146 first remains failed: MostlyText `024103b3` with Textual
`ff74cf54`, hosted run
[42450824327](https://github.com/Joncallim/mostlytext/actions/runs/42450824327),
Debug/revision initial 55/56. The first image Copy passed; the new document
generation returned plain fixture text after the bounded wait. The resource
trace showed a decoded PNG but selected layout with zero attachment runs.

The later private `.task(id:)` diagnostic first remains failed: MostlyText
`fd93b11e` with Textual `e75d3a1`, hosted run
[42525800028](https://github.com/Joncallim/mostlytext/actions/runs/42525800028).
The revision-mutant cell also failed its supposedly unaffected generation
Copy. Its trace localized the missing delivery between an offered attachment
layout and the selected model. This was a different handoff from shipping
`.onChange`; it does not establish the cause of the original failure.

The six-pair run
[42537565253](https://github.com/Joncallim/mostlytext/actions/runs/42537565253)
on MostlyText `14997864` and Textual `45d5ef2d` passed all six
Debug/Release and revision/viewport/disappear cells with ten mounted image
generations per cell. It is diagnostic-only and does not by itself establish
causality or qualify a shipping change.

The controlled A/B holds one app/test checkout, one hosted macOS 26 Apple
Silicon environment, the same selected mounted Copy test and the same
resource trace. The old variant resolves Textual `d2f8488476a26a1c22d173026bcd7b231cd75b4a`,
which retains shipping `.onChange` selection behavior with passive
load-ID-correlated trace. The new variant resolves Textual
`45d5ef2d9a2d0d993de265ffeba7697db97799f5`, whose substantive
selection change is the coalesced main-actor handoff. Only the app's Textual
pin metadata may differ. The workflow rejects an added or changed unrelated
package, a changed app/test source, a mismatched Xcode checkout, or a changed
compiled app/test binary.

Each variant runs the unchanged test ten times through separate app-hosted
test invocations. Each invocation itself copies distinct image pixels over
ten document generations and checks 100 negative pixel controls. Raw
XCResults, event logs, per-generation selected model IDs and attachment
state, input and compiled binary hashes, and the first failing invocation
are retained. A selected-test mismatch or timeout stops the cell; an actual
test failure is retained and further bounded invocations continue.

If the old variant reproduces the selected-layout failure while the new
variant passes under these common inputs, the handoff change has supporting
causal evidence. If both pass, both fail, or either cell lacks complete
source/native receipts, causality remains unresolved. No result from this
private workflow closes PR #146, issue #13, or release acceptance.

## First controlled-run harness failure

The first exact-head A/B dispatch, MostlyText `9feb6e45` run
[42574557016](https://github.com/Joncallim/mostlytext/actions/runs/42574557016),
reached the old variant's guarded dependency resolution. Its retained
`ab-inputs.json` records Textual `d2f84884`, exactly four changed pin metadata
files, and all other 23 package pins unchanged. The first failure occurred in
the next source-only control: its fixture read the already switched worktree
lock as if it were the committed new-variant baseline. The log records
`ValueError: The source is not the exact private new-variant lock`. The
always-run immutable-lock check then found no generated Xcode project,
because the workflow had stopped before generation. No native app build or
Copy test ran; the new variant remained queued and the workflow was cancelled
for a scoped harness correction. This failure is not evidence for or against
the selection handoff hypothesis.
