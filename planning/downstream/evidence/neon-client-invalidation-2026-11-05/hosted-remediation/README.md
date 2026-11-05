# Remediate the first hosted deletion failure

The first PR #78 head passed the strengthened selection-replacement control,
but CI41968571963 failed the existing below-cutoff deletion comparison. One wide
italic range (1706 through 1969) erased several narrower styles beyond the
queried dirty region. The complete first failed log is retained with its digest.

The actual warmed client plus actual named-range styling adapter reproduces
this independently: applying one partial query to an already-correct reference
overwrites neighboring bold styles. Two assertions fail before clipping. The
owner fork e528a19381bfe3bc0ea996f41dcea11efbc2e9f0 clips emitted tokens to the
requested range while preserving order and name mapping. Empty/disjoint cases
have a separate strict control. The final component suites pass Debug/Release:
34 Swift Testing functions across nine suites plus eight existing XCTest cases.
The earlier twelve-assertion client baseline and its failed hosted run remain.

OwnedStylingCore compiles Token.swift unchanged and the exact Foundation-only
prefix of TreeSitterClient+Neon.swift. verification.json records the selected
byte range and digest. The native conditional tail is excluded. This is not
whole-file source identity or local native/text-view execution. All other
Foundation/C fixture rules, excluded Rearrange UI helpers and grammar bytes
remain unchanged. fixture-inputs.json records the current inputs.

The real HighlightingTests target compiles with locked resolution and local
lint passes. Full corrected-head hosted CI remains required; this reproduction
and correction are not a passing rerun of the original native adapter check.
The separate buffered-coordinate repair must carry this correction as well.
