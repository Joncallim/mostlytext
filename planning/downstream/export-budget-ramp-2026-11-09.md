# Export budget graduated Release ramp

This is an exploratory follow-up to the three-case actual-path calibration in
draft PR #160 (`8f595b22`). It gathers more evidence for issue #11 on a
disposable hosted macOS 26 arm64 runner with Xcode 26.6. It does not set a
final budget, establish native acceptance, or change a production limit.

## Execution boundary

The workflow builds the Release app and test bundle once, then launches a
fresh, owned `xcodebuild test-without-building` process for each case. Each
Swift Testing case calls the public `ExportService.exportHTML` path with a
real admitted local resource directory. Fixture creation, CRC verification,
hashing and post-run inspection happen outside the measured app process.
The same source hash, 24 dependency pins, toolchain, app binary, fixture
hashes, one-test XCResult and test transcript are bound in receipts. A
successful output is checked against the app's byte count and digest before
the large HTML file is deleted from the runner. Refusals must leave no
published file.

Only a same-repository pull request or explicit workflow dispatch can run
the hosted job. Both the Python controls and the Swift probe check the
runner account and exact temporary path. There is no owner-desktop launch.

## Graduated cases

The low tier covers 8 MiB source, 8 MiB single PNG, 16,384 occurrences,
three references to one 32 MiB PNG, three distinct 32 MiB PNGs, and 128
distinct small PNGs. The
middle tier covers 24 MiB source and single PNG, five repeated 32 MiB
references, and four distinct 32 MiB PNGs. The upper tier reaches exactly
32 MiB source and single PNG, then 65,536 occurrences and 512 distinct
resources. Four additional
cases exercise the first excess URL slot (65,537), six repeated 32 MiB
resources that exceed the 256 MiB final HTML cap, and a fifth distinct
resource after the 128 MiB aggregate cap, and a 513th distinct resource.
The last two cases are unresolved resource policy refusals; the URL slot
and final HTML excess cases are budget errors.

The source-size cases are mostly whitespace after a short heading so the
source gate is measured without also hitting the derived HTML gate. The PNGs
are valid 1-by-1 images with deterministic CRC-protected ancillary data,
made outside the app to test real local image reads and base64 expansion.

Each case has a 180-second ceiling, the entire sequence has a 30-minute
ceiling, and the sampled app plus newly seen same-user WebKit helper RSS has
a 1.5 GiB ceiling. A reached ceiling or failed case terminates its owned
process and stops the remaining ramp; partial receipts remain in the
artifact. These are conservative *measurement* stops, not recommended
product limits. RSS is sampled, and attribution of new WebKit helpers is
observational. A stopped or incomplete run fails verification.

## Remaining evidence for issue #11

The baseline PR #160 measures a real multi-page WebKit/PDFKit export, but
neither it nor this HTML ramp measures a PDF near the provisional 256 MiB
output ceiling. A separate, carefully bounded PDF workload and review of
actual peak memory, helper memory, timing, output integrity and refusals are
needed before freezing final budgets. Owner/test-desktop native acceptance
and signing remain separate gates. No checklist item should be marked done
from source-only checks or a partial hosted run.
