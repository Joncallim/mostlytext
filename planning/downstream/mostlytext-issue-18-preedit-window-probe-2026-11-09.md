# Issue #18: conservative pre-edit Markdown window probe

## Owner summary

The earlier viewport experiment selected a Markdown window from a fresh
**post-edit full parse**, so it could not reduce per-keystroke work. This
source-only follow-up tries a narrower case: replace an interior word in a
punctuation-free, single-line paragraph. It selects the visible root sections
from the **pre-edit tree** and parses only that edited window. Three 1 MiB
fixtures match the full post-edit parser's visible root, inline and combined
captures. Five structural, marked-up or oversized cases refuse a window.

No production highlighter, parser pin, size fallback, editor behavior or
resource limit changes. This is a feasibility result, not the 50 ms typing
path or a promise that arbitrary Markdown edits are window-safe.

## Selection and refusal

The candidate selector starts with an existing pre-edit root tree and the old
source. A candidate requires one clean root section, a direct child paragraph
containing the edit, an interior replacement of nonempty alphanumeric text
with nonempty alphanumeric text, and a paragraph containing only letters,
numbers, spaces and tabs (plus its terminal newline). It refuses any
paragraph over 65,536 UTF-16 units before scanning its text. Binary search
over ordered root children then selects every section overlapping the visible
span. An out-of-bounds or over-65,536-unit resulting window also refuses.
Those values are diagnostic stops for this probe, not product thresholds.

The selector never reads a post-edit tree. A fresh full post-edit parse is
created **after** selection solely as a test oracle. The test compares
visible-clipped capture names and UTF-16 ranges from the full and window
parses for root Markdown, the inline sublayer and their combined layer.
Each positive requires at least one actual visible capture.

## Focused Release result

`swift test -c release --force-resolved-versions --filter MarkdownPreEditWindowProbeTests --no-parallel -j 6`
passes on a local Apple silicon Mac. Each starting fixture is 1,048,576
UTF-8 bytes. The middle and start plain paragraphs each select a 227-unit
window; the Unicode word case selects 225 units. Each has 4 root, 1 inline
and 5 combined visible captures, all exactly equal to the full post-edit
oracle. A fence opener edit, list marker edit, heading word edit, paragraph
with emphasis markup, and 70,000-character paragraph all refuse before
window parsing. The focused test takes about 20 seconds because it builds
pre-edit and oracle full parses; that duration is not typing latency.

## Remaining engineering proof

This selector deliberately rejects most real edits, including punctuation,
newlines, deletions, marked-up paragraphs and large blocks. A production
path needs a safe result for those refused edits, an invalidation model for
multiple edits and viewport motion, text-version ownership, nonlocal
reference/injection checks, actual Release app-path measurements, and a
qualified strategy for the current 8,192-unit Markdown size fallback.
No native UI or signed-artifact acceptance is inferred. Issue #18's
50 ms keystroke criterion remains open.
