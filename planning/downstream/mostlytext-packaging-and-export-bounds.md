# MostlyText packaging names and bounded final HTML

## Owner summary

Release packaging must select the real mostlytext command and retain the embedded helper. Export must refuse a final HTML document that exceeds its safety ceiling before publication or PDF loading, including repeated references to one image. These are independently testable source units; they require no signing credentials, native application execution or separate account.

## Baseline and scope

Integration baseline is e2a66c257957f61391128dba1cfe839a23b8fd52; frozen master is 15c0fae22f7618e94c82681227057c66011be2a9. Public CLI is mostlytext, scheme MostlyTextCLI, embedded executable Contents/MacOS/mostlytext-cli. MacDown2 app target/product filenames remain deliberate internal names; this work does not rename them, change version/build policy, sign, notarize, install a CLI alias or publish anything. Native acceptance and #519/#520 holds remain.

## Unit 1: release command packaging

Use MostlyTextCLI and mostlytext throughout the existing locked release pipeline. Check that both the standalone command and embedded helper are produced as regular executable files before signature/notarization stages. Record their actual identities in evidence. Keep source/workspace pin checks, mode-specific compliance behavior and every signing/distribution stop condition. Fixtures model current Xcode schemes and products, reject obsolete names, and test missing/non-executable helpers and public CLI ZIP/hash names. Run only stubbed release tests locally: no real credentials or Apple submission.

## Unit 2: final HTML assembly

ExportService owns a checked UTF-8 assembly sink and the single trusted final-HTML budget (256 MiB initially, as already proposed in #118 architecture; not a measured performance claim). Self-contained and companion APIs become throwing and share the gate. Account for the complete template, escaped metadata, stylesheet/head and each repeated embedded resource occurrence, using checked arithmetic before base64/allocation and each bounded append. A counting pass admits the whole shell and body before rendering, including closing markup; a second checked pass emits bytes. The original body is scanned with cached next matches for the three directory representations, preventing quadratic rescans for absent forms. Unused resource payloads are not encoded. Keep cancellation checks in expensive assembly. Reject before output mutation or PDF loading; propagate the existing budget error through ordinary callers. Tests inject tiny internal budgets for cap-1/cap/cap+1, repeat amplification, metadata/style overhead, overflow and cancellation. Preserve normal HTML bytes and existing raw-HTML/resource-resolution policies.

The current textual resource replacement still needs registered URL slots to eliminate authored-text collisions. Input resource lease/grant integration, output directory/sidecar authority and recovery, exact external-writer exclusion, final Release memory calibration and native PDF/HTML journeys remain #118/#121/#183 work. This bounded size gate does not close those issues or claim peak-memory calibration.

## Verification and completion

Land the two units separately. For packaging: actual scheme/product declarations, all stubbed release/Compliance tests, shell syntax and tree inventory. For final assembly: focused Foundation-only source-bound Debug/Release controls, strict lint/format, compile-only local app/tests, complete hosted package/app tests and locked Debug/Release builds. Keep every initial failure. Self-review is labelled as such. Before each integration-only merge, require completed exact-head checks, a merge tree equal to the tested tree, and unchanged frozen master; verify the actual merge afterwards. Update canonical issues with bounded implementation completion and retain native/release gates.

## Source verification record — 2 November 2026

Packaging landed in #564 at 3cb65cfba288029215148a2c962f099538620b3b, tree equal to tested head 0f7b907b6b60f18771c58bffdc756cd5fda4b1f2; hosted Compliance 41411013482 passes. All 99 local Compliance tests, shell syntax and inventory pass. The old script fails the strict scheme control. The initial ZIP-absence assertion was corrected because MacDown2.zip is the app archive on a case-insensitive filesystem; the fixture now checks the archived executable path.

Final HTML controls use byte-identical production writer/template/budget/file-writer sources in a private non-application Swift package, with only the unused validated-publication dependencies stubbed. Eleven Swift Testing tests pass Debug and Release, including complete UTF-8 boundaries, repeat amplification, escaped metadata/head/styles, URI overflow, unused resources, cancellation, false-prefix scanning, no materialization before whole-document admission, and no destination/sidecar mutation on rejection. Bypassing the final cap must fail the repeated-resource control. Initial initializer-access, scratch-budget and lint/format failures are retained. This is self-review and source/control evidence; it is not native PDF acceptance or memory calibration. The localized new budget detail is registered for final #17 review.

## 7 November2026 packaging reconciliation

The separate `mostlytext` build product remains a regular executable and is
signature-checked; the supported installed command resolves to the containing
app's `Contents/MacOS/mostlytext-cli` through an explicit user-created symlink.
The [app-bound distribution correction](embedded-cli-distribution-2026-11-07.md)
removes the unsupported executable-only CLI ZIP from future public output.
The app/DMG retain all signature/notarisation and exact-artifact gates. No
historical download, native acceptance, signing or promotion result is changed.
