# Issue #18: one-character pre-edit window probe

## Scope

The earlier pre-edit probe admitted three interior word replacements in a
1,048,576-byte Markdown source. This follow-up tests the issue's actual
one-character insertion shape without changing the production parser, Neon,
editor assists, highlighting fallback, or dependency pins. Its baseline is
MostlyText `main` at `5630c2f3`.

A zero-length edit cannot intersect a tree node. For a single alphanumeric
scalar inserted strictly between two existing alphanumeric UTF-16 units, the
selector probes the old unit after the insertion point. It still requires one
clean section, a direct plain paragraph, no markup or punctuation in that
paragraph, and a window no longer than 65,536 UTF-16 units. A space-boundary
insertion is refused. The five existing structural and oversized refusals
remain in the same test. An unpaired surrogate at either neighboring unit
cannot become a candidate.

## Local Release observation

The locked focused command
`swift test --package-path MacDown2/Packages/MacDownKit --force-resolved-versions -c release --jobs 4 --no-parallel --filter MarkdownPreEditWindowProbeTests`
passed **1 test / 1 suite** on local Apple silicon. The test count is unchanged
because these are additional specimens inside the existing test. Every
starting source has 1,048,576 UTF-8 bytes. The pre-edit selector admitted
three inserted `x` characters and the visible root, inline, and combined
capture names and UTF-16 ranges matched a fresh full post-edit parse.

| Insertion | Window, UTF-16 units | Matching captures, root/inline/combined | Selection | Window substring + parse | Full oracle parse |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mid-document word | 231 | 3 / 1 / 4 | 0.089 ms | 0.156 ms | 1.829 s |
| Document-start section word | 231 | 4 / 1 / 5 | 0.067 ms | 0.179 ms | 1.857 s |
| Word beside Unicode text | 230 | 3 / 1 / 4 | 0.083 ms | 0.180 ms | 1.807 s |

The space-boundary insertion and all five prior structural/oversized cases
were refused. The three earlier word-replacement cases still matched. Strict
SwiftLint and SwiftFormat on the changed test file and `git diff --check`
pass. The full command log is held outside the repository at
`/private/tmp/mostlytext-issue18-insert-release.log`.

These are one-run component timings, not stable ceilings. Selection assumes
an already available pre-edit tree; the window timer excludes editor text
mutation and capture comparison. The full oracle is measured separately and
is never used to select the candidate. The test creates no editor view or
application process.

## Remaining gate

This test-only probe accepts a deliberately narrow word insertion. Real
typing includes punctuation, boundaries, deletions, multiple edits, viewport
motion and nonlocal Markdown state; those paths need a safe fallback and
versioned invalidation before a production window parser. The current
Markdown size policy reduces highlighting above 8,192 UTF-16 units, so this
probe cannot establish full-color 1 MiB editor behavior or issue #18's
50 ms whole-keystroke requirement. Native Release responsiveness and the
final artifact remain separate evidence.
