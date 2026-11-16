# Export resource budget policy — 16 November 2026

## Owner summary

New exports admit at most 64 MiB of distinct local resources. That is the
largest aggregate-resource tier published by the actual Release export ramp.
Larger self-contained cases already exceeded the 128 MiB complete-HTML limit;
the new gate refuses them during resource admission. Existing authenticated
companion exports written under the former 128 MiB cap remain eligible for
bounded recovery and retention. This change does not publish an app, alter a
resource grant, or qualify the final save-panel journey.

## Measured inputs and outputs

The [20-case actual Release ramp](https://github.com/Joncallim/mostlytext/actions/runs/43659019930)
ran on a disposable macOS 26.7.2 ARM host with Xcode 26.6 at source
`675ebcf35fc950c3b29ec6874e61fbf7ed30a889`. Each case ran in a fresh app
test process. The retained artifact has the fixture manifest, source receipt,
per-case result, sampled memory and result bundle. Relevant observations:

| Case | Result | Output | App high-water RSS |
| --- | --- | ---: | ---: |
| 32 MiB source | published | 6,754 bytes | 450,183,168 bytes |
| 32 MiB single image | published | 44,746,050 bytes | 439,074,816 bytes |
| 512 distinct images | published | 99,830 bytes | 183,566,336 bytes |
| 65,536 image occurrences | published | 9,957,120 bytes | 402,636,800 bytes |
| 64 MiB distinct resources | published | 89,485,346 bytes | 696,500,224 bytes |
| 64 MiB minus 8 KiB, repeated near final cap | published | 134,213,718 bytes | 876,216,320 bytes |
| 96/128 MiB distinct resources | refused by final HTML cap | none | 282,296,320 / 316,112,896 bytes |

The [six-case actual Release export](https://github.com/Joncallim/mostlytext/actions/runs/43814263133)
at source `b1365355a8fe278f31e6bc3a21cbbdb294d2eb9e` also covered derived
content. All six tests passed without skips: 4,096 fragments (262,144 derived
HTML bytes) exported in 0.050 seconds; 1,024 fragments carrying 32 MiB of
derived HTML exported in 2.205 seconds, producing 33,562,174 output bytes.
The latter test host's high-water RSS was 532,840,448 bytes. These are
fixture-specific measurements; sampled WebKit helper memory is separate.

## Policy and compatibility

`ExportResourceBudget.standard.maxAggregateResourceBytes` is 64 MiB for new
requests in every output mode. The same definition continues to own source,
single-resource, resource-count, derived, prepared-HTML and final-HTML gates.
The 20-case ramp supplies standard-boundary publication/refusal evidence;
smaller injected-budget tests exercise exact arithmetic and no-publication
behavior. The new exact-head ramp expects 96/128 MiB cases to refuse during
resource resolution rather than during complete-document assembly.

The separate `maxPreviouslyManagedResourceBytes` is 128 MiB only for
authenticated recovery and bounded retained-asset inspection. It does not
admit 128 MiB into a new export. The existing 256 MiB managed-output allowance
likewise only permits inspection of historical output receipts. Unknown or
altered files remain protected by the existing ownership checks.

## Remaining qualification

The expanded same-branch Release calibration must measure escaped Markdown
near the prepared/final HTML ceiling. The 20-case ramp must be rerun on the
revised policy to prove the earlier 64 MiB success and earlier 96/128 MiB
refusals retain their expected outcomes at the new admission point. Resource
read-work, passive Quick Look and PDF limits still have their own provisional
status. The exact release-candidate menu/save-panel journey and broader native
visual acceptance remain separate issue #11 criteria. Preserve the first
failed calibration and any new negative result; do not turn these measurements
into a claim of signed release readiness.
