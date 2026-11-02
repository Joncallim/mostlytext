# MostlyText packaging names and bounded final HTML

## Owner summary

Release packaging must select the real mostlytext command and retain the embedded helper. Export must refuse a final HTML document that exceeds its safety ceiling before publication or PDF loading, including repeated references to one image. These are independently testable source units; they require no signing credentials, native application execution or separate account.

## Baseline and scope

Integration baseline is e2a66c257957f61391128dba1cfe839a23b8fd52; frozen master is 15c0fae22f7618e94c82681227057c66011be2a9. Public CLI is mostlytext, scheme MostlyTextCLI, embedded executable Contents/MacOS/mostlytext-cli. MacDown2 app target/product filenames remain deliberate internal names; this work does not rename them, change version/build policy, sign, notarize, install a CLI alias or publish anything. Native acceptance and #519/#520 holds remain.

## Unit 1: release command packaging

Use MostlyTextCLI and mostlytext throughout the existing locked release pipeline. Check that both the standalone command and embedded helper are produced as regular executable files before signature/notarization stages. Record their actual identities in evidence. Keep source/workspace pin checks, mode-specific compliance behavior and every signing/distribution stop condition. Fixtures model current Xcode schemes and products, reject obsolete names, and test missing/non-executable helpers and public CLI ZIP/hash names. Run only stubbed release tests locally: no real credentials or Apple submission.

## Unit 2: final HTML assembly

ExportService owns a checked UTF-8 assembly sink and the single trusted final-HTML budget (256 MiB initially, as already proposed in #118 architecture; not a measured performance claim). Self-contained and companion APIs become throwing and share the gate. Account for the complete template, escaped metadata, stylesheet/head and each repeated embedded resource occurrence, using checked arithmetic before base64/allocation and each bounded append. Keep cancellation checks in expensive assembly. Reject before output mutation or PDF loading; propagate the existing budget error through ordinary callers. Tests inject tiny internal budgets for cap-1/cap/cap+1, repeat amplification, metadata/style overhead, overflow and cancellation. Preserve normal HTML bytes and existing raw-HTML/resource-resolution policies.

The current textual resource replacement still needs registered URL slots to eliminate authored-text collisions. Input resource lease/grant integration, output directory/sidecar authority and recovery, exact external-writer exclusion, final Release memory calibration and native PDF/HTML journeys remain #118/#121/#183 work. This bounded size gate does not close those issues or claim peak-memory calibration.

## Verification and completion

Land the two units separately. For packaging: actual scheme/product declarations, all stubbed release/Compliance tests, shell syntax and tree inventory. For final assembly: focused Foundation-only source-bound Debug/Release controls, strict lint/format, compile-only local app/tests, complete hosted package/app tests and locked Debug/Release builds. Keep every initial failure. Self-review is labelled as such. Before each integration-only merge, require completed exact-head checks, a merge tree equal to the tested tree, and unchanged frozen master; verify the actual merge afterwards. Update canonical issues with bounded implementation completion and retain native/release gates.
