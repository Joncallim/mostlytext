# Mounted Markdown viewport Release measurement

The production `SyntaxHighlightStore` still constructs the highlighter with
`enableViewport: false`. The opt-in session, painter and public highlighter
benchmarks on current main are a useful next gate before considering a default
change. This slice makes their timing records precise and repeatable on a
disposable macOS 26 Release runner. It changes no application behavior.

The workflow checks out the pull request's exact head, records the source,
package lock, two benchmark sources, workflow, OS and Xcode identities, and
runs both existing 1 MiB mounted-editor benchmarks in optimized SwiftPM mode.
Its verifier requires the complete named tests, twelve edit measurements in
each case, the 1 MiB source size, and all twelve local cache admissions in the
viewport cases. It retains raw logs and structured measurements even when a
later step fails. The measured times are observations, not a raised threshold
or a hidden pass against the 50 ms product target.

## Local preparation observation

On the owner Mac's Xcode 26.6 optimized package host, the exact changed test
sources passed. The mounted session's twelve edit calls measured 9.551–37.082
ms and settled paint 11.845–38.650 ms; all twelve proposals paired and used
local parsing, with one initial full parse. In the public highlighter comparison,
the existing reduced mode's edit/settlement range was 8.766–55.721 ms, while
opt-in viewport mode measured 3.811–41.304 ms for calls and 6.299–43.637 ms
for settlement. Its twelve edits paired and parsed locally, with one initial
full parse. Both tests restored the original 1,048,804-byte source.

The reduced-mode 55.721 ms outlier is retained, not averaged away; a second
verifier run reached 58.004 ms in reduced mode while viewport settlement
remained at or below 38.641 ms. The initial
full parse took about 0.7 seconds in these package-host runs. Neither case
measures a complete release app's key event, Preview, OS draw completion,
WebKit helpers or 8 ms main-actor target. No owner product was launched. The
hosted measurement and the broader structural edit, IME, undo, viewport and
native Release controls must be reviewed before enabling viewport mode.

## First hosted result and toolchain correction

The first exact-head [hosted measurement](https://github.com/Joncallim/mostlytext/actions/runs/43521210074)
at `6be6b43f` executed all three cases and retained its complete artifact.
That workflow chose the first Xcode 26 installation, which was Xcode 26.0.1
on macOS 26.7.2, rather than the Xcode 26.6 used by the export/Release gates.
Its twelve-edit settled medians were 89.052 ms for the mounted session,
90.929 ms for reduced mode and 93.191 ms for viewport mode; viewport reached
131.863 ms. The measurement workflow itself passed because it records rather
than silently waives a product threshold. This is negative performance
evidence for that exact worker/toolchain, not a 50 ms qualification.

The follow-up chooses exactly Xcode 26.6 using the established export-workflow
selection loop and fails setup if unavailable. Keep the first timing record;
review the fresh same-toolchain measurement before deciding whether to tune
TextKit/editing, continue the reduced fallback or enable viewport colour.
