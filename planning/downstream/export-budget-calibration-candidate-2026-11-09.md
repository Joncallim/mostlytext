# Export budget measurement candidate — 9 November 2026

## Owner summary

MostlyText has size limits that prevent an export from consuming unbounded
resources, but several limits are still provisional. This slice prepares a
repeatable Release measurement on a disposable macOS 26 runner using the real
ExportService, WebKit print path and PDFKit readback. It changes no product
behavior or limit. The first run can reveal a failure or guide a larger test
matrix; it cannot by itself check MostlyText #11's final calibration row.

## Baseline and ownership

The source baseline is `main` at
`d605d92ed6adc196bf0e679461dd8896443f6847`. `ExportResourceBudget`
currently admits 32 MiB of Markdown source, 512 distinct resources, 32 MiB per
resource, 128 MiB aggregate resource payload, 4,096 derived fragments, 32 MiB
derived HTML, 128 MiB prepared HTML, 65,536 generated image URL occurrences,
4,096 resource read attempts, 256 MiB read work and 256 MiB final HTML. The PDF
adapter separately admits at most 256 MiB of generated PDF bytes. The final
HTML, image-occurrence, read-work and PDF limits are explicitly provisional.

ExportService continues to own composition and HTML publication.
`PDFExportAdapter` continues to own WebKit loading, printing, PDFKit validation
and PDF publication. This slice adds only an opt-in app test, hosted workflow,
memory observer and evidence checks. It adds no dependency, app-facing string,
authority or new export path.

## Measured journeys and refusal

1. A generated, one-pixel PNG is referenced 2,048 times in Markdown. The test
   calls the public `ExportService.exportHTML` self-contained path, checks all
   embedded occurrences and records source/output hashes, bytes, elapsed time
   and the app test host's resident-memory high-water mark.
2. A 25-section Markdown document with the same local PNG is prepared through
   `ExportService`, assembled by `PDFExportAdapter`, printed with actual WebKit,
   validated with PDFKit and read back for both endpoint headings. The test
   records prepared HTML/PDF bytes, page count, hashes, preparation/print times
   and app-process high-water memory.
3. A 32 MiB plus one-byte source is submitted to the production HTML entry
   point. The expected budget refusal must leave the selected output absent.

An external observer samples the exact app executable's RSS every half second.
It separately records same-user WebKit helper processes first seen after the
run starts. That helper cohort is an approximate envelope, not proven
per-document attribution. The app's `getrusage` high-water value does not
include WebKit helpers. Neither metric alone is whole-system peak memory.

## Execution and evidence boundary

The workflow runs on a same-repository pull request, and can be manually
dispatched after the workflow exists on the default branch. GitHub does not
dispatch a newly added workflow from a feature branch alone. It uses a
disposable GitHub macOS 26 ARM runner, selects Xcode 26.6, generates the
actual project, enforces all 24 locked
package pins, builds the Release app/test bundle and executes only the three
opt-in tests through the existing owned native-test supervisor. Its native
command has a 600-second bound; the observer has a 650-second bound; the job
has a 45-minute bound. Host checks refuse the owner and test-account paths.

Before compilation, a receipt binds the clean checkout, selected source and
workflow hashes, lock graph and toolchain. The final verifier requires all
three functions to pass once in both the log and result bundle, the owned app
binary hash to match the built binary, normal bounded supervisor exit, all
three measurement records and nonzero app/WebKit observations. The artifact
retains the result bundle, logs, measurements, memory samples and receipts,
including a failed first run. No test is retried into a pass without diagnosis.

The local preparation gate is Python pure tests, Python compilation, Swift
parse, SwiftFormat/SwiftLint and diff checks. No owner-account product or
package runtime is part of that gate.

## Stop and next measurement decision

Do not freeze or raise any limit from these small fixtures. A first hosted run
must establish whether the actual path executes and whether the measurement
can identify both app and WebKit memory. Then design graduated, bounded cases
near each production ceiling, including repeated large images, non-image and
failed reads, source/prepared/final HTML growth, PDF output growth and retained
renderer state. Measure peak memory and wall time across repeated Release runs
before choosing any lower or higher limit. Preserve cap-minus-one/cap/cap-plus-
one refusal behavior and no-publication guarantees for each changed gate.

The public menu/save-panel journey, complete-operation cancellation, native
test-desktop acceptance, exact signed release candidate and whole-app memory
outside this hosted fixture remain separate #11/#8/#4 gates. The #11 budget
checkbox stays open until the expanded measurements support a final policy.
