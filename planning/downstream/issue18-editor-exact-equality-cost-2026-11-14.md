# Exact editor text comparison in the 1 MiB edit path

The production Markdown highlighter still uses the bounded reduced fallback.
The hosted Xcode 26.6 mounted-editor measurement at [PR #274 head
`9b0f0873`](https://github.com/Joncallim/mostlytext/actions/runs/43524230663)
measured twelve local word edits on 1,048,804 bytes: settled medians were
81.619 ms for the mounted session, 74.155 ms for reduced highlighting and
84.397 ms for the opt-in viewport highlighter. The viewport maximum was
120.742 ms. The measurement job passed its completeness checks; these times
fail the 50 ms product target and do not authorize viewport activation.

An optimized local TextKit 2 isolation probe on unchanged main `7e5fd167`
compared the same editor with and without its coordinator. Twelve insertions
with the coordinator attached took roughly 35–48 ms after the first edit;
the same mounted text system, scroll view, ruler and hosting view with the
coordinator detached took roughly 0.56–0.9 ms. Manual coordinator publication
after a bare insertion took roughly 35–37 ms. The source getter and gutter
width update were below 0.2 ms in this probe. A same-source `String` exact
comparison on the NSString-backed 1 MiB editor text took roughly 34–35 ms,
matching the publication delay. A native Swift string took roughly 2.75 ms.

`String.isExactlyEqual(to:)` previously compared UTF-8 iterators to preserve
the exact authored scalar sequence across persistence and editing. For this
bridged editor text, the iterators are expensive. An attempted `withUTF8` and
`memcmp` path still took roughly 36 ms because it first materialized the
bridged string, so it was rejected. Literal `NSString.isEqual(to:)` took
roughly 6–7 ms on the same bridged source and preserved the required
distinction between canonically equivalent but differently encoded strings.
Valid Swift scalar sequences map injectively to UTF-16 code units; literal
UTF-16 equality therefore preserves the old exact-scalar decision. The new
regression compares both native and bridged strings against an independent
UTF-16 oracle, including embedded NUL, combining marks, non-BMP and variation
sequences. A large bridged source checks equal text and final-unit differences.

In a local optimized package-host run after this helper change, the opt-in
public highlighter's reduced-mode edit/settled times were roughly 7–8 ms;
viewport edit calls were roughly 7–8 ms and settlement roughly 9–11 ms in
the same 1 MiB twelve-edit fixture. Before the change, reduced mode was
roughly 34–40 ms with 55–58 ms outliers and viewport roughly 36–44 ms.
These are local, exploratory before/after observations, not a hosted product
budget pass. Re-run the exact-head Xcode 26.6 measurement and full CI; retain
the original 50 ms limit and the separate native Release acceptance gate.

## Production follow-through

The app's `SyntaxHighlightStore` still constructs `NeonSyntaxHighlighter`
without `enableViewport`. Once the hosted exact-head timing is reviewed, a
separate production activation must exercise store ownership, mounted edits,
scroll/return visits, theme/font/language changes, structural fallback,
replacement, undo/redo, IME and teardown. `MarkdownViewportSession` admits a
bounded local word window; unsupported edits deliberately schedule a deferred
full parse and show plain text while that result is pending. The twelve local
word edits alone cannot qualify all of these paths or a complete app event to
paint budget.
