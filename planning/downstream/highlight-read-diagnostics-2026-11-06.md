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
