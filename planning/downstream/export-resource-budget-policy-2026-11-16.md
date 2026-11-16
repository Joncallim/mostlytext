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

That [20-case rerun](https://github.com/Joncallim/mostlytext/actions/runs/43817242196)
passes at source `a62f599ab88368353c96214f4f59ca97f9ffc4eb`: 64 MiB
distinct resources publish 89,485,346 HTML bytes at 695,386,112-byte app
high-water RSS; the almost-128-MiB repeated output publishes 134,213,718
bytes at 874,364,928-byte high-water RSS. The 96 and 128 MiB cases refuse
before publication with resource-resolution diagnostics. The 32 MiB source,
512-resource and 65,536-occurrence cases also retain their expected published
outcomes. Per-case result bundles, fixture hashes and memory samples are in
the run artifact.

The separate `maxPreviouslyManagedResourceBytes` is 128 MiB only for
authenticated recovery and bounded retained-asset inspection. It does not
admit 128 MiB into a new export. The existing 256 MiB managed-output allowance
likewise only permits inspection of historical output receipts. Unknown or
altered files remain protected by the existing ownership checks.

## Escape-heavy source finding and repair

The [first expanded Release calibration](https://github.com/Joncallim/mostlytext/actions/runs/43817100991)
passed its seven functional cases at source `fd1ed0524948ded7125a00572da9519dc8c1e7fa`,
but its 24 MiB line of ampersands exposed a performance failure: 125,835,839
HTML bytes, 24.134 seconds and 3,408,986,112 bytes app high-water RSS. The
complete-document output fit the 128 MiB final cap, so that cap could not
prevent memory growth during parsing and escaping. The source and output
SHA-256 values, process samples and exact test bundle are retained in the run
artifact. The green test result is not a safety pass.

The repair counts a conservative upper bound on source characters that may
expand into HTML entities before invoking cmark. It allows up to 16 MiB of
potential extra bytes, independently of the 32 MiB source cap. Four MiB of
ampersands reaches that allowance exactly; one extra ampersand and the retained
24 MiB trigger must refuse before parsing and preserve a preexisting output.
The actual prepared/final HTML limits remain in place for generated content.
This is a targeted bound on the observed escape-heavy path, not a general
proof of constant parser memory for every Markdown grammar. The new diagnostic
enters the ExportService String Catalog as an English source and marked
review-needed French, Japanese and Polish drafts for final issue #3 review.

## Remaining qualification

The final exact-head Release calibration must measure the 4 MiB accepted
escape boundary, the plus-one and historical refusals, and both read-work
limits. Read-work values remain provisional until that run passes and its
memory/latency are reviewed. Passive Quick Look and PDF limits have separate
provisional status. The exact release-candidate menu/save-panel journey and
broader native visual acceptance remain separate issue #11 criteria. Preserve
the first failed calibration and any new negative result; do not turn these
measurements into a claim of signed release readiness.
