# Bound the default D2 WebKit page count

## Owner summary

Two D2 diagrams can create two large WebKit content processes at once. Use one
warm D2 page by default so ordinary Preview and Export requests queue through
the existing bounded pool. Keep the same D2 engine, output, source preservation
and offline authority. An explicit two-page pool remains available to callers
that have separately measured a need for it. This is a resource-policy slice of
issue #7, not a final memory ceiling or static Quick Look implementation.

## Current source and decision

The implementation baseline is `main` `d01b700ccbf361de50766a3ba4a64b24eb0f9763`.
`D2WebRenderer` currently defaults to two lazily constructed
`DiagramHarnessPage` slots, each backed by WebKit. `DiagramWebKitPool` already
owns queueing, a 15-second admission timeout, a separate five-second script
timeout, cancellation and shutdown. No new state, interface or entitlement is
needed for a one-slot default.

The earlier [two-request Release run 44409737625](https://github.com/Joncallim/mostlytext/actions/runs/44409737625)
rendered distinct graphs in 4.483 seconds. Newly seen WebKit helpers peaked at
778,944,512 RSS bytes; the broader sequential D2 control reached 942,489,600
bytes. Nine post-shutdown samples found no newly seen helper. That run did not
prove a leak or an app-wide memory bound.

The same-run [one/two-slot comparison 44452733760](https://github.com/Joncallim/mostlytext/actions/runs/44452733760)
uses the same two source hashes and SVG outputs under locked Release on macOS
26.7.2. Two slots completed both in 5.446 seconds and peaked at 1,489,027,072
sampled helper RSS bytes; one slot completed both in 3.189 seconds and peaked
at 709,459,968 bytes. Both modes had zero newly seen helpers three seconds
after shutdown. Runner and WebKit scheduling vary; these observations justify
removing an unnecessary simultaneous D2 page in the default policy, not a
claim that one slot always renders faster or stays below a particular RSS cap.

## User journeys and invariants

- Two ordinary D2 fences render with their own source ranges and preserve
  readable source on a renderer refusal. Queueing cannot overwrite a newer
  generation or extend the existing per-script deadline.
- A document with several D2 fences may queue; six simultaneous requests must
  complete in the existing 15-second admission window on the hosted Release
  fixture. If this fails, retain the two-slot policy and inspect the first
  failure rather than raising the timeout.
- Cancellation and shutdown still retire the page. The sandbox, network,
  source-size, output-size and timeout controls remain unchanged. Mermaid and
  Graphviz keep their current pool policies.
- This does not change authored bytes, exports' SVG semantics, localization,
  Quick Look's separate three-second child, or D2's bundled runtime.

## Evidence and stop conditions

Use the retained two-slot and one-slot fresh-process sampler results as
comparative evidence. Run the existing D2 rendering suite with the production
default serving six concurrent requests; keep explicit two-slot pool coverage
in the lower-level pool tests. Run the locked Release D2 budget cases with
source/output/deadline refusals and a mixed renderer document, plus the exact
source's selected CI suites, normal Release build, lint and compliance. A
native final-candidate memory and interaction matrix remains open under #7.
Do not check its aggregate memory-limit criterion from these samples alone.
