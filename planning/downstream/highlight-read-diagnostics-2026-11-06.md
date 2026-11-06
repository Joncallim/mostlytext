# Capture the original Debug highlighting read failure

## Owner summary

Issue #19 still lacks the exact parser read offset, snapshot boundary and text
length at its original Debug assertion. Collect those values from the real
editor/highlighter without altering the dependency or suppressing the assertion.
This is a diagnostic prerequisite, not a fix or proof of safe Release behavior.
The separately signed-in owner acceptance remains open.

## Baseline and boundaries

Start from main ee45cc25d43c9cf6b067ad4d2674312a96f7cb1e. Keep every dependency
pin and shipped source byte unchanged. Use only generated Markdown and an owned
hosted macOS 26 test helper. Never run this native fixture in the owner's GUI
session. Do not change the original String+Data.swift assertion, read callback,
range limits, editor notifications or grammar timing to obtain a result.

## Diagnostic slice

Compile the real Highlighting, EditorCore and grammar products in Debug. Copy
all original HighlightingTests into a temporary package, rejecting any fixture
that needs source-relative resources. Record original and copied hashes. The
only temporary fixture change removes the disabled-in-Debug annotation from
widenedBackgroundTypingMatchesAFreshHighlighter; its body and assertions stay
byte-identical. Select only that original test. This is explicit opt-in
execution of a previously held experiment, never a replacement for the suite.

Launch a separately copied and ad-hoc-signed SwiftPM helper under the hosted
LLDB debugger. Break on the original assertion line, capture byteOffset, limit,
chunkSize, location and end from that frame, bounded evaluation of the captured
String's UTF-16 count, the thread stack and the original assertion. Continue
into the unchanged failure. Keep the original native logs even if the debugger
cannot resolve a variable or the fixture no longer reproduces. Such a result
is inconclusive, not a successful diagnostic. Bound compile to 15 minutes and
execution to 10 minutes; keep output, source inventories, dependency pins and
helper hashes. Do not publish document content or invoke an external service.

## Completion and next decision

The slice is qualified only when the actual selected function executes and the
original failure yields all requested values from an unchanged dependency.
Compare the observed request with the captured snapshot and inspect its actual
caller before classifying a legitimate end-of-input read or a stale range.
No issue checkbox, dependency patch, upstream contact or production remediation
is authorized by a mere debugger stop. A demonstrated fix needs a controlled
mounted edit/reload/undo interleaving and fresh-highlighter parity in both
Debug and Release, followed by full combined checks and independent review.

## Controlled background language-resolution slice

The first 113ec5ed hosted diagnostic executes the intended Debug function and
resolves the real assertion breakpoint, but the original abort does not occur.
The original expected-issue wrapper instead reports that no highlighting mismatch
was recorded. There is no assertion-frame file. Retain this as non-reproduction
under a debugger; neither a root cause nor a fix follows from it.

Add a nil-by-default internal observation hook immediately before the real
injected-language provider lookup, outside the configuration cache lock. The
public initializer and every shipped call retain nil. A test-only initializer
supplies the hook without replacing a grammar, parser, snapshot or renderer.
Hold only the first actual background JavaScript request using a bounded
semaphore, signal its arrival to the test, then replace/shrink/grow the mounted
real TextKit 2 editor before releasing the request. Never block a main-thread
lookup; missing background entry fails the control. Compare nonempty final
rendered runs against an independent fresh real highlighter and preserve exact
source bytes. Keep the control opt-in until the original read path is classified.
This explicitly extends the diagnostic architecture to a small internal testing
hook; it does not permit changes to dependency reads, limits or assertions.

The controlled fixture mounts the actual EditorView and EditorTextSystemStore
before attaching the production highlighter. Its real coordinator owns source
publication; require that delegate, exact bound-model bytes and advancing
contentRevision as well as the native text/style checks. A manually attached
NSTextView without the coordinator would omit the app's edit bookkeeping and
would not prove this integration path.

The first coordinator-mounted revision compiles, but LLDB's run command tries
to shell-expand the combined test-filter expression and lldb-argdumper exits
127. No selected fixture executes in that attempt. Launch with explicit literal
arguments using process launch --shell-expand-args false, and require actual
selected-function start before classifying missing assertion values. Preserve
the original setup failure separately from the earlier genuine non-reproduction.

## Separate strict replay coverage from original-trigger classification

The c9224d40 owned Debug run really holds the background JavaScript request,
replaces/shrinks/grows the actual EditorView, preserves native and model bytes
and matches a nonempty fresh highlighter. The controlled test passes. The old
widened experiment also reports no mismatch, causing its stale expected-issue
wrapper to fail; neither reaches the original assertion. No triggering numbers
exist. Preserve those results without treating them as a root-cause fix.

Use the exact stricter canonical widened fixture from PR99 source 37e6fde0:
nonempty fresh output and exact parity, with no expected-issue wrapper. Retain
the ordinary Debug guard; only these explicitly opted-in owned runs enable it.
Add a direct run before the Debug debugger to expose debugger timing effects;
Release runs the same two strict real-editor controls directly. No assertion,
read bound, deadline, dependency or style expectation changes.

Record two independent outcomes. Successful assertion capture still requires
every requested real value and continuation into the original fatal error. If
no assertion occurs, qualify only complete strict replay selections (including
the held-request marker) in every requested mode and explicitly record that the
original trigger remains unresolved. Missing/failed controls, setup failures,
timeouts or incomplete frame values fail. A green replay check cannot satisfy
issue #19's original-numeric-trigger or failing-before remediation criteria.
This replaces the earlier assumption that a successful current regression must
reproduce the historical abort; it does not weaken those root-cause criteria.

## Validation against the merged editor theme semantics

Reconcile this branch with actual main fcf2674420c2712056086df16437925f8bf5f411.
The earlier 70ba1779 full CI passed 3704 package functions in 529 suites and
670 app functions in 140 suites; both strict controlled replay configurations
also passed. Those runs predate the merged theme source. Require fresh combined
checks before integration. The added opt-in highlighting function and suite are
included in the complete current-line test inventory, increasing its exact
candidate count from 1082/142 to 1083/143. Keep the historical two-failure
baseline and the actual orientation mutation and restoration controls intact.
The original assertion trigger remains unresolved; no issue acceptance is
inferred from a current replay passing.

## Investigate repeated Release ceilings without bypassing qualification

Final combined source c99eb37a again executes all 1083 editor/theme functions
and fails only the existing 400 ms direct-parser ceiling (411.439834 ms). The
previous c1db source also failed it and the 500 ms full-highlight ceiling.
The performance fixtures, grammar factory and immutable runtime pins are
unchanged from the earlier PR99 occurrence; no timing cause is inferred.
The original full selection remains failed and cannot qualify this PR.

On a complete failed Release selection naming HighlightPerformanceTests,
collect a bounded fresh-process replay of the unchanged direct-parser test and
the complete unchanged performance suite. Use the same compiled test binary,
owned helper, pins and thresholds; preserve both success and failure statuses.
Record CPU model/core/memory metadata and current toolchain, plus the existing
owned-process identity/status/stack evidence. This distinguishes a failure that
also occurs in an isolated process from a possible full-suite interaction;
either outcome is a repair or a green original selection. No retries of the
full suite are added and the existing job/execution limits remain unchanged.
The diagnostic source and owned-executor source are part of immutable receipts.
All native execution stays on hosted macOS 26; no owner GUI launch is permitted.
