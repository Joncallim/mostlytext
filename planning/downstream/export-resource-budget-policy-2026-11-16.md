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

The first repair counted a conservative upper bound on source characters that
may expand into HTML entities before invoking cmark, allowing 16 MiB of
potential extra bytes. Its [exact-head Release calibration
43820790739](https://github.com/Joncallim/mostlytext/actions/runs/43820790739)
failed the memory criterion: the accepted 4 MiB ampersand source produced
20,978,239 HTML bytes in 2.082 seconds, but drove the app test host from a
412,712,960-byte previous high-water to 1,379,942,400 bytes. Because that
high-water persists in the same process, the plus-one and historical refusal
checks also failed their under-1-GiB assertions even though each correctly
preserved the destination. The other seven tests passed, including both
derived limits and the read-work refusals. The failed ten-test result and all
twelve case receipts remain available in the run artifact.

The revised guard allows up to 4 MiB of potential extra bytes, independently
of the 32 MiB source cap. One MiB of ampersands reaches that allowance
exactly; one extra ampersand and the retained 24 MiB trigger must refuse
before parsing and preserve a preexisting output. This tighter gate is a
measured safety response, not a formatting preference. It may conservatively
refuse a large valid document containing much literal punctuation.
The actual prepared/final HTML limits remain in place for generated content.
This is a targeted bound on the observed escape-heavy path, not a general
proof of constant parser memory for every Markdown grammar. The new diagnostic
enters the ExportService String Catalog as an English source and marked
review-needed French, Japanese and Polish drafts for final issue #3 review.

## Remaining qualification

The [revised exact-head Release calibration](https://github.com/Joncallim/mostlytext/actions/runs/43827792734)
passed ten app tests without failure or skip at source `3217374a` (synthetic
checkout `9d284a2c`). The 1 MiB ampersand boundary produced 5,249,599 HTML
bytes in 0.549 seconds at 636,436,480-byte app high-water RSS. The plus-one
and retained 24 MiB source refused before parsing in 0.004 and 0.026 seconds,
respectively, preserving the previous destination; their app high-water was
unchanged. The 4,096-fragment and 32 MiB derived-HTML cases passed in 0.067
and 3.103 seconds. The 4,097-attempt and 256 MiB charged rejected-read cases
refused without output in 0.380 and 0.062 seconds, at 849,543,168 and
883,113,984-byte app high-water RSS. The process sampler observed at most
803,110,912 app bytes across the complete run. The full twelve-case receipt,
source hashes, built-app identity, test result and process samples are retained
in the run artifact. These results support the source, derived, read-work and
escape-work limits as the frozen Export policy for this source.

The [new exact-head 20-case ramp](https://github.com/Joncallim/mostlytext/actions/runs/43827792735)
also passed with fresh app processes at the same product source: 64 MiB of
distinct resources published 89,485,346 HTML bytes at 381,730,816-byte
sampled app RSS; the near-final 134,213,718-byte output published at
832,421,888 bytes. The 96 and 128 MiB aggregate cases refused before
publication. All twenty case results, fixture hashes and memory records are
retained in its artifact. The first failed calibration remains a failure;
neither later success changes its result nor proves constant parser memory for
all possible Markdown.

Passive Quick Look and PDF limits have separate provisional status. The exact
release-candidate menu/save-panel journey and broader native visual acceptance
remain separate issue #11 criteria. These measurements do not qualify a signed
release candidate.
