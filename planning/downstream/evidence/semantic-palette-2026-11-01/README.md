# Shared palette and bundled-theme foundation

Source `ed1bfb898d31d1a064e497de07d7e73ff8af7070` passed the locked,
serial pure-theme/presentation selection: **34 tests in five suites**.
The tracked source was clean before and unchanged after execution. Commands,
OS/toolchain, result and log hash are in validation.json; the complete log is
retained alongside it. No application or native UI test was launched.

The unit adds one immutable semantic palette for editor/Preview/export and six
original bundled themes, retaining the two stable default IDs. GitHub Light's
display name now matches its verified provenance; its ID/file name remain for
settings compatibility. Bundled body/link/code contrast and high-contrast body
checks pass. A minimal dark fallback keeps selected text readable.

Source compliance and all 92 compliance fixture tests passed. New JSON resources
are registered with first-party MIT provenance and exact hashes; generated
notices/SBOM follow the inventory. Six other strict release-compliance findings
remain, including source availability and deeper linked-code attribution.

The first selected run failed a newly written background-uniqueness assertion:
two deliberately different light palettes both use white. The corrected test
requires distinct complete chrome/token palettes, without making different
background colors a product requirement. Its failing log remains locally in
the CORTANA build directory. The next run passed; the final run above also
covers the subsequent dark fallback selection correction.

The package build reports existing selector warnings in EditorUndoPublicationTests;
this unit introduces no corresponding production change. Full app/Release,
combined integration, visual/VoiceOver, custom-theme and Finder/Quick Look
acceptance remain open. The source tests and generated inventory are not E23
or release clearance.
