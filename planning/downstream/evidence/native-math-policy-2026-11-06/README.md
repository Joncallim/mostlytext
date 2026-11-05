# Native placement/font baseline probe preparation

Prepared exact actual tests for display classification through accessibility
wrappers and font-only attachment metric refresh. Current owner ebf6590a remains
unchanged. The new tests retain positive base/control checks and fixed native
50 x 10 ms / depth 24 / 512-node limits, own window cleanup, and a bounded public
self-process AX request. Local native/product/signing execution remains held.

Actual PreviewTests compiles (7.55 s), scoped strict lint/pinned formatting pass.
The initial nested-private Observable macro conformance failed to compile;
fileprivate access fixes this test setup without API/assertion changes. Exact
before source and failed raw log are retained. Four exact native/support sources
now prepare into the existing three immutable application-pin fixture. Five
explicitly synthetic format/verifier controls pass and their synthetic log is
deleted. Source/pin tamper controls from the parent implementation remain.

Native execution has not occurred for these new probes. Run only the focused
hosted workflow first to capture the actual baseline, preserve all failures,
and remediate only proved behavior. Complete full CI remains required before
merge; no original whole-feature/native acceptance criterion is inferred.
