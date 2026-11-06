# Reject cancelled and superseded immediate Markdown publications

## Owner summary

An earlier document parse must not publish after the session cancels it or
accepts newer input. Keep the preceding accepted Preview intact until current
work completes, while reporting that physical parsing is still outstanding.
This is a narrowly scoped continuation of MostlyText #17's async publication
review; it does not diagnose the historical tree-sitter assertion or qualify
an owner-native journey.

## Current baseline and observed gap

Actual clean main is d607098bdb5046c02d81137b497e0ffe1aa01748. Read the root
AGENTS.md, EPIC_STANDARD.md and RELEASE_HARDENING.md. MarkdownParseSession
increments pendingGeneration for immediate/debounced requests and cancelPending,
but only cleanup checks that generation. Its parse completion checks caller
cancellation and already-published revision, so an uncancelled immediate caller
can publish after cancelPending, or while a newer request remains outstanding.
The public cancelPending contract explicitly promises no publication. Existing
held-engine busy tests check physical accounting, and must remain unchanged.
JSONAnalysisSession already checks generation at its publication boundary; this
unit does not change that separate implementation or its return-value contract.
The app's initial Markdown load, parse options and edits share this session.

## Scope, ownership and invariants

Change only MarkdownParseSession and canonical MarkdownEngine regression tests,
plus self-contained component evidence and required documentation. No public
interface, dependency/pin, parser algorithm, worker admission, cancellation
mechanism, debounce value, resource grant, source normalization or native policy
changes. Keep actual immediate work counted until its physical await returns,
including cancelled/superseded work. A dropped immediate completion returns nil,
consistent with the existing cancelled-caller contract. Retain previous accepted
document/publishedText/count on cancellation or supersession. Current immediate
and debounced requests still publish normally. Revision ordering and original
busy-state/error/cancellation tests remain.

## Implementation and failure-first evidence

1. Add three deterministic held-engine regression functions using the existing
   GatedParseEngine: cancellation before any publication and after a valid seed;
   older immediate completion before a newer held immediate parse; and immediate
   completion after a newer debounced edit has been scheduled. Require unchanged
   accepted state, nil dropped return, exact counts/busy state and a subsequently
   successful current publication. No timed sleeps establish the interleaving.
2. Reproduce failures against byte-identical actual main MarkdownEngine sources
   in an inspected standalone Foundation console, with a real source inventory,
   exact locked Markdown/Yams/cmark dependencies and bounded execution. No local
   app, public CLI, native helper, AppKit, SwiftUI, WebKit or drawing execution.
   Canonical tests compile locally and execute only in appropriate hosted checks.
3. Pass the captured pending generation into the private parse function and
   compare it after the engine await, before any publication. Do not cancel or
   decrement another operation's physical busy count or clear newer pending work.
4. Run the identical before/after standalone cases, preserve all first failures,
   verify only intended source changes and all immutable pins, run strict tools
   and full required hosted package/app/build checks. Incorporate actual main
   changes and fresh combined evidence before integration. No unchanged retry,
   deadline/threshold waiver or old receipt retargeting.

The controlled engine substitutes only completion timing and returns the actual
MarkdownDocument type. It does not mock session publication or physical state.
Normal console linkage must be inspected before execution. Native stress,
original byteOffset/limit classification, signed-release and independent rights
review remain their own open criteria. Do not close a whole issue from this fix.
