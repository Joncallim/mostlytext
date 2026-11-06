# Make parser performance fixtures meet their advertised sizes

## Owner summary

The parser's advertised 1 MB and 10 MB baseline fixtures currently contain only
945,500 and 9,599,818 UTF-8 bytes. Their fixed iteration count assumes every
mixed Markdown block is as long as one paragraph; several blocks are shorter.
Generate until the requested byte bound is actually reached, keeping the same
mixed headings, lists, quotes, code, tables and prose. Preserve both existing
time ceilings. This corrects measurement inputs, not parser performance.

## Baseline and scope

Main ee45cc25d43c9cf6b067ad4d2674312a96f7cb1e. Change only the deterministic
MarkdownEngineTests fixture, its byte-bound controls and this reconciliation.
No parser source, dependency, application behavior, source fidelity or public
resource authority changes. No new dependency or API.

## Execution and proof

Replace the fixed paragraph-estimate loop with a repeat-until-byte-bound loop,
retaining at least one complete block for zero-sized requests.
Do not pad with unrelated bytes, cut a Markdown block or lower a requested size.
Check both decimal MB and binary MiB requests, including exact UTF-8 counts.
Use the actual old fixture as a failing-before control and exact restored new
source as passing-after. Native application execution is unnecessary; inspected
Foundation-only fixture execution and compilation are permitted. Full hosted
package/app CI still has to pass; preserve any genuine performance failure.

## Limits

Issue #18 remains open: whole-document incremental behavior, original Release
keystroke budgets and whole-path measurements are not proved by a corpus fix.
The first unchanged Intel run at PR99 source 37e6fde0 measured its undersized
10 MB corpus at 75.404 seconds against the unchanged 60-second Debug ceiling.
That failure and one unchanged retry remain separate evidence; corrected larger
inputs must not turn it into an accepted budget result by changing the limit.
