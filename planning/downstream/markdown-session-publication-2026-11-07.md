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

## Preserve the native adapter fixture's single publication owner

The first bc8da866 Release app integration completes29 functions/9 suites and
fails21 assertions:9 heading navigation,3 math live-source and9 math navigation
cases have no current parse. Keep its exact source/pin/normal-owned-exit receipt
and full log. The generation guard must not be weakened to accommodate this.

Those adapter tests intentionally remove the SwiftUI workspace and mount the
registered TextKit editor directly, but their shared factory first constructs a
WindowController with an active Markdown document. That creates a real workspace
with initial parsing/options tasks before the content is removed. A manual
parseNow then competes with that separate producer. The comment promising no
initial-SwiftUI race is therefore not established by the old construction order.
The production load calls setOptions, which deliberately schedules reparsing even
for equal options; the original OptionsTests requirement stays unchanged.

Give the internal WindowController initializer an optional initial content
controller, default nil. With nil it constructs exactly the existing workspace
root; no production caller changes. The direct-adapter test factory supplies an
empty native content controller before WindowController is initialized, so a
SwiftUI workspace and its parse producer are never created for that fixture.
The actual model/tab/controller, eager real editor/parser stores, source provider,
window and manually mounted NSScrollView/NSTextView remain. Merely constructing
an empty model and removing its placeholder before inserting a tab cannot prove
that an asynchronously dismantling SwiftUI graph will never observe that tab.
Use the explicit content ownership boundary instead of timing that teardown.

The shared test factory's default-true mountWorkspace path retains all original
text-filter fixture behavior. Only the direct math/heading helper opts out. Move
the constructor to a test support extension if needed to retain original strict
source-size limits. Preserve all29 selected functions,21 original positive/
negative navigation assertions, key-window/focus/selection/scroll/parser-replacement
checks and every deadline. Real full-workspace heading/source/Preview journeys
remain in their separate tests. No shipping option, alternate parser, private
state mutation, public package API or parse/options policy is added.

Local work compiles only; fresh complete hosted Debug/Release app integration and
normal package/app CI are mandatory. Until then the21 failures remain unresolved
evidence, not a claimed production cause or proof that the fixture was the only
issue. Do not infer a historical Debug-assertion diagnosis or whole-issue closure.

## Combined qualification amendment — 7 November 2026

The owner-authorised E08 integration follows
[release-source-convergence-2026-11-07.md](release-source-convergence-2026-11-07.md).
The exact unit history remains an ancestor of the combined source. Incorporate
all reviewed units before publication of the integration candidate and require
all original positive, negative, mutation/restoration, source/pin and full CI
gates again on that single final source. This supersedes a requirement to merge
each intermediate source separately before assembling the next unit. Main
remains unchanged until the complete combined candidate qualifies. Original
failed/pending results retain their own SHA and outcome; no historical receipt
is retargeted or ceiling/deadline/selected assertion weakened. Owner-account
native execution and final release gates remain held.
