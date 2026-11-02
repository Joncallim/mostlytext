# Export resource slots and ordinary publication safety

## Owner summary

A self-contained export should replace only the generated image references that ExportService owns. Authored examples, navigation links and raw HTML must keep their exact bytes even when they resemble a managed resource path. Ordinary HTML must also stop following an existing assets-directory symlink or claiming an unfamiliar directory. These source units can be exercised with private filesystem fixtures without launching the app, using signing credentials or accessing another account.

## Baseline and boundaries

Integration baseline: 6b44e3da5f45a131e912f7b9e289bac9b4515139. Frozen master: 15c0fae22f7618e94c82681227057c66011be2a9. Follow issue-118-handoff.md and the existing E12 pipeline. Retain all source/prepared/final budgets, offline policy, raw-HTML target rules and source preservation. No dependency, native PDF bridge, preview grant activation, signing or release changes. EXECUTION_HOLD remains; local app/test targets compile only. #519/#520 retain their native-before-integration holds.

## Unit 1: generated resource URL slots

The composer creates a transient registry with an opaque ASCII namespace absent from the source, destination component, stylesheet and derived fragments. Only a successfully resolved cmark image URL receives a unique occurrence token. A trusted provisional ceiling of 65,536 registered occurrences bounds registry storage before HTML rendering; tests inject a tiny cap. The cmark URL callback can throw, so over-cap registration frees the tree and aborts before render-buffer allocation rather than accumulating unusable markers. This new safety ceiling needs the same empirical Release calibration as the other provisional limits. Images/links inside an image description have no emitted URL and do not register a slot. Resource reads and immutable manifest identity remain owned by the existing resolver; this does not settle the separate input-grant/TOCTOU requirement.

After rendering, a bounded quote-aware byte scanner recognizes actual img/src attribute values, skipping comments, declarations and raw-text elements. It resolves exactly one emitted attribute per registered token into an encoded companion URL, recording the resulting UTF-8 range, expected attribute bytes and admitted identity. Unknown, duplicate, missing or misplaced tokens fail closed. Bind the private slot table to the exact completed body digest. The public prepared-document initializer grants no substitution authority; manifest-bearing manually constructed documents require trusted internal registration before self-contained assembly.

Final assembly verifies the binding, ordered nonoverlapping ranges, exact expected bytes and manifest identities before the counting pass. Embed only registered occurrences under the existing final sink. Companion output remains byte-identical to the prepared body. Never infer authority by scanning canonical filenames. Preserve normal output and deterministic prepared values; opaque tokens never reach a published document. Tiny-budget tests and a before/after authored-path collision control are required.

## Unit 2: ordinary publication boundary

Refactor the existing descriptor-relative validated writer so ordinary HTML uses the same anchored staging mechanics, without enabling the optional SVG path. Serialize publication by opened parent directory identity. Reject sidecar symlinks and existing directories without an exact recognized primary-bound owner marker; preserve ambiguous legacy/unknown output and ask for another export name. Existing content-addressed resources are reusable only when bounded no-follow reads match their expected bytes. Stage complete HTML privately, revalidate parent/directory/resource identities and observed primary baseline, then promote primary last with cancellation checked at the synchronous cutoff. Bind same-stem sidecars to the exact primary leaf, so .html/.htm and case variants cannot silently share ownership. Public errors must be localized and preserve prior output.

This is a bounded authority/staging unit. Inventory-backed journals, quarantine retirement, safe stale retention ceilings, authorization-time destination baselines, arbitrary external-writer exclusion and native filesystem/menu acceptance remain separate #118/#183 gates. No cleanup by filename pattern and no claim that a precheck plus rename is compare-and-swap. Any limitation found in this narrower boundary stays explicit rather than being hidden by green tests.

## Verification and landing

Use source-identical non-application Swift harnesses in Debug/Release, real cmark where needed, synthetic private filesystem fixtures, strict SwiftLint, SwiftFormat 0.63.1, Compliance and unsigned compile-only app/tests. Retain first failures and before/after controls. Full exact-head hosted package/app tests and locked Debug/Release app/mostlytext builds must finish before each integration-only merge. Self-review is labelled; do not claim independent review. Require a clean tree, merge tree equal to tested tree and frozen master before merge; verify the actual merge tree afterwards. Update #118/#183/#115/#17 only to the demonstrated extent and keep remaining gates open. Preserve worktrees during merged-branch cleanup and refresh the readiness audit.

## Unit 1 source evidence

Twenty-two source-identical non-application tests pass in Debug and Release with the locked real cmark implementation. The current pipeline with the previous writer fails the authored-path collision regression; the slot writer passes. The hosted suite additionally exercises the actual composer/resolver/manifest integration using private image fixtures. Strict SwiftLint, pinned SwiftFormat 0.63.1, all 99 Compliance controls, inventory and unsigned app/UI-test compilation pass. Initial cancellation-fixture, throwing-callback compile and lint/format failures are retained with their corrections. This is self-reviewed source evidence; native acceptance and memory calibration remain open. The publication boundary above is a separate unit, not implemented by the slot change.
