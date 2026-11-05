# Carry partial-query containment into the buffer repair

The first PR #79 run passed the newly strict combined typing/deletion and
selection replacement controls. It failed only the existing below-cutoff
comparison, reproducing the same partial-style problem as PR #78. The complete
failed hosted log and digest are retained. This supports the buffer correction
at that head without claiming the whole run passed.

Owner fork 9db7e1d361d6f724ee28da49eae532db3018b408 merges the independently
reproduced query-containment repair with the buffer correction. Both public
named-range initializer signatures remain; only their authorized output range
is enforced. The actual client/adapter reproduction and selected Foundation-only
source-prefix provenance are retained in the client evidence packet carried by
this merge. No native conditional tail executes locally.

All exact Foundation/C component suites pass Debug/Release: 39 Swift Testing
functions in ten suites plus eight existing XCTest cases, including 75,772
geometry cases, client callbacks, partial-style containment and the unchanged
stress test. The full real HighlightingTests target compiles with forced locked
resolution. Source inventory and all 316 Compliance controls pass after metadata
generation. New full hosted CI remains required before merging this exact head.
