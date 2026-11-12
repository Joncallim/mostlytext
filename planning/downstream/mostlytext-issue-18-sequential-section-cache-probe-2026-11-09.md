# Issue #18: indexed section-cache feasibility

## Indexed follow-on — 12 November 2026

The test-only cache now stores section displacement in a Fenwick difference
index. Its accepted plain-word edits preserve section count; a changed window
replaces its own section trees and applies one suffix shift in O(log n) time.
Lookup of a later or earlier section likewise takes O(log n), independent of
the number of accepted edits. The replacement sections subtract the current
displacement when they are installed, so earlier shifts cannot be applied to
their newly parsed local offsets a second time.

On clean main `4478bf08` plus this probe, one 1,048,576-byte input survived
14 successive replacements alternating between two paragraphs and a return
viewport visit, with **no full parse between edits**. After the entire
candidate sequence, independent full post-edit parses matched every saved
root, inline and combined visible capture name and UTF-16 range in all 15
states. The heading-edit refusal still passed. The final local optimized
Release run took 29.210 seconds including all full-oracle parses; each
candidate select/local parse/cache update/visible capture took 0.246–0.425 ms
in that run, and the return visit took 0.052 ms. Host: Apple M3 Pro,
macOS 26.5.1, Xcode 26.6. Command: `swift test -c release
--force-resolved-versions --filter MarkdownSectionCacheSequentialProbeTests
--no-parallel` from `MacDown2/Packages/MacDownKit`.
The same final-source Debug selection also passed all 15 capture comparisons
in 45.280 seconds; candidate operations took 0.784–1.170 ms and the return
visit 0.243 ms. These are fixture observations, not product ceilings.

This is still a narrow parser-only feasibility result. It does not handle
insertions at boundaries, structural Markdown edits, section-count changes,
arbitrary Unicode, concurrent revisions, or a failed local parse. It retains
the initial whole-document tree and does not connect to Neon's private
highlighter tree or apply AppKit attributes. The 50 ms whole-editor and 8 ms
main-thread budgets remain open. A production design needs bounded offset
arithmetic, structural-edit invalidation, revision ownership and an adapter
that can retire obsolete trees without stale paint.

## Earlier two-edit probe — 9 November 2026

## Owner summary

The pre-edit window test in PR #189 proves one narrow paragraph edit can
choose a small Markdown parse window from an old tree. This follow-up asks
whether a cached set of root sections can survive another accepted edit and
a viewport move **without an intervening full parse**. It can for the two
plain-word edits tested here. This is a source-only feasibility result; the
app still uses its existing 8,192-UTF-16-unit Markdown highlighting fallback.

## What the test proves

The initial source is exactly 1,048,576 UTF-8 bytes. One full parse populates
the cache before timing. The test then replaces an interior word in each of
two nearby plain paragraphs, moving the visible range from the first to the
second and back. The cache retains the old trees for unaffected sections,
parses only each selected replacement window, and maps captured ranges back
to global UTF-16 offsets. Its section lookup uses binary search. A fixed
two-edit shift log keeps its per-edit offset lookup bounded for this probe.
It refuses a heading edit and a third edit before parsing another window.

The test saves the candidate captures after each edit and the return visit.
Only **after** those candidate operations does it make fresh full post-edit
parses as independent oracles. Root, inline and combined visible capture
names and UTF-16 ranges match for all three views; each view has 3 root,
2 inline and 5 combined captures. The two candidate windows are 251 and
249 UTF-16 units. The final locked local Release run reports 0.491 ms and
0.288 ms for selection, local parse, cache replacement and visible capture;
the return visit reports 0.091 ms. The complete test, including full oracles,
takes 7.519 seconds. These are one-machine observations, not product budgets.

## Limits and next decision

The accepted class is only nonempty alphanumeric replacement inside a clean,
punctuation-free, single-line paragraph. The two-edit cap is a diagnostic
stop, not a proposed product threshold. The probe retains a whole-document
initial layer and does not measure first-open time, memory, an indefinite
edit sequence, structural edits, scrolling under concurrent work, attribute
application, redraw, source geometry, or app main-thread stalls. The existing
Neon `TextViewHighlighter` owns its tree privately, so this cache cannot be
connected to the editor without a reviewed dependency adapter and revision
ownership. No production source, dependency pin or highlighting threshold
changes here. Issue #18's 1 MiB / 50 ms whole-editor target and 8 ms
main-thread target remain open.

The next source experiment should replace the two-edit shift log with a
persistent ordered section index, exercise many edits and viewport moves,
and compare captures against deferred full oracles across more edit classes.
Only then should an editor adapter be considered for a test-account Release
build and measured native acceptance.
