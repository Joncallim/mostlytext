# Theme and Appearance compile/test evidence

Exact app source: `0b78b3a26659e85d054fa7966ec64a5baae33db1`.
CORTANA, macOS 26.5.1, Xcode 26.6, arm64, locked dependencies.

- Release app build: PASS, 204.72 seconds; Release CLI: PASS, 4.58 seconds.
- Debug app/test build-for-testing: PASS, 171.16 seconds. Tests were not launched.
- Archived tracked source remains unchanged; package pins match after builds.
- 114 selected package tests in 13 suites: PASS. Their complete package Swift
  input manifest matches this source revision. This includes 34 original
  palette/controller/preview/export tests, strict theme-file cases, import
  decisions and source-faithful FileCore decoding/encoding regressions.
- Full SwiftFormat and strict SwiftLint: PASS.
- 92 compliance fixture tests and tree check: PASS, zero unverified tree items.
- Release compliance: FAIL, six explicit source/attribution obligations remain.
  The misnamed light-theme item was resolved through verified provenance;
  source publication and unrelated attribution requirements were not waived.

The settings tab, sample and translation drafts compile. No application,
Finder Quick Look, VoiceOver or pseudo-localization visual check ran here.
Native focus/layout, every-theme visual review, source/selection/undo retention,
custom file persistence/management, registered Quick Look and independent
source review remain required. These results do not close #113 or #115.

Xcode registers app build products with Launch Services even during compile
checks. That side effect was identified and the exact generated product URLs
were unregistered after the checks, without launching them or resetting the
Launch Services database. Runtime isolation is still a separate #88 gate.
