# Public CLI stdin readback and save qualification

## Owner summary

Prove that piped Markdown reaches the ordinary document editor, can be saved
through the normal Save panel, and retains its exact UTF-8 bytes. Also prove
that the same ad-hoc development build refuses an untrusted cold launch instead
of silently bypassing its existing signature requirement. This is an engineering
rehearsal on a disposable hosted Mac; successful Apple-trusted cold launch and
installed signed-helper acceptance still require the signed candidate.

## Baseline and readiness

Baseline main: `427d15fa5da94d4045a02e7f6a005648d09e38c5`.
Issue #4 is the product contract. Existing native-cli-probe verifies six warm
comparisons but does not read back or save the stdin document. Its last stdin
process uses force cleanup, which does not prove normal Quit. Public command is
`mostlytext`, explicitly symlinked to the existing embedded
`Contents/MacOS/mostlytext-cli`; no independent distributable is added.

Inspection of CommandLineConnection and EmbeddedCommandApplication reconciles a
false planning assumption: ad-hoc hosted builds deliberately fail verifyForLaunch
because the embedded helper must have a valid team and the app must satisfy an
Apple-anchored matching-team requirement. There is no unsigned-launch override.
Do not implement one or present a normal helper launch as a cold-client success.
Current-main Preview qualification PR132 is frozen; this private lane can be
prepared now but its execution is held until that candidate is qualified and its
actual main integration is recorded. No product changes are authorized here.

## Journeys and state transitions

1. A fresh guarded hosted macOS26 ARM account has no current/development product
   stores/defaults or running product. A genuine harmless input/button test passes,
   then actual unlocked console/input metadata is recorded.
2. Invoke the public symlink once with a generated file while the ordinary app is
   absent. Expect the existing unavailable exit5 and no product process. Check
   absence using a strict read-only identity helper that never opens the app or a
   socket. Preserve its exact result; do not retry an unchanged failure.
3. Launch the ordinary ad-hoc Release app using the existing normal app controller.
   Preserve Welcome without acknowledging it. Obtain actual process identity and
   live socket peer, then pass a generated UTF-8/LF/NFD/emoji payload to the public
   symlink. The actual app has no test flags, injection or overridden defaults.
4. Attach the independent UI driver only to that existing PID/birth/app digest.
   Verify the unique editor's complete bytes against the generated oracle. Use
   normal File > Save As, navigate to the generated folder and save a fixed name.
   Verify the saved document window and editor bytes. Controller reads the physical
   saved file, compares exact bytes/hash, and checks the original source unchanged.
5. Terminate the same actual process normally; unsaved-input recovery must already
   be resolved by the save. Recheck physical output, product/helper/generated/source
   identities and all original assertions. Force teardown is failure cleanup only.

## Boundaries, failure policy and interfaces

New private fixture/controller/workflow only. Keep all existing warm CLI, focus,
licence, status, migration, original UI and signing guards byte unchanged. Copy the
existing genuine control and strict host facts into the generated fixture, bound
by canonical hashes. Reuse the normal app controller without extending it.
A new private read-only absence helper checks runner UID/account/home/OS/repository,
no owner paths and the exact fixed output root before querying running processes.
It refuses any running product and never has a launch/terminate/connect operation.
The driver binds actual PID, exact launch date, bundle/executable and SHA256 before
calling activate, so XCTest cannot conceal a missing ordinary launch. No claim
about pre-activation focus is made. Welcome must remain visible and its original
acknowledgement key absent before/after the CLI request.

Use the existing fixed mostlytext-focus preparation contract for app/helper/licence
resources/source/generated binding, inside its exact guarded root. Overlay a copied
private stdin driver plus generated oracle values before sealing generated hashes;
never edit a previously sealed generated manifest. The specialized controller owns
one receipt extension and runs the existing prepared-source verifier before/after.
The standard controller's five-criterion verdict is not reused for this journey.
Capture before/after app/helper bytes, the actual independent control/driver/runplan,
raw xcresult/owned status, complete first logs and UI/Save-panel attachments.

No retries, assertion removals, larger deadlines, expected failures, test skips,
product flags, signing keys, privileged state, publication or CORTANA native launch.
Any first SDK/Save-panel/ordinary-product failure stops qualification and remains
failed. Preserve complete results before architecture/material correction. Output
is wholly owned in a fresh hosted root; no existing file is overwritten.

## Slices and completion

A. Commit this source-based architecture before implementation.
B. Prepare guarded private specialization, exact generated source/compiled/result
   binding, actual stdin/Save-panel assertions and a manual-only workflow. Source
   controls must prove host/optimized/held admission occurs before generated writes
   or any launch, and reject changed bytes/phase/identity/results.
C. Intake actual qualified Preview main, replace the explicit pending dependency
   only after its integration proof, run one first complete hosted selection, and
   independently inspect original logs/artifacts/raw results/physical bytes.
D. Review/merge only if every genuine control and original assertion passes; record
   the scoped #4 evidence. Keep its installed/trusted-cold/signing/update/final rows
   open. Test source alone is not native acceptance.

## Validation and limits

Locally: Python/Swift syntax, strict source/style checks, real-filesystem generated
input/result contracts and counterfactual guards only. No local product runtime.
Hosted: ordinary pinned Release build, independent genuine control, unavailable5
cold refusal, one warm stdin/Save As UI case, exact physical UTF8 bytes and normal
identity-bound Quit. Exact signed/installed state, trusted cold success, quarantine,
Gatekeeper, updates, localised/VoiceOver and owner/protected acceptance remain open.

## Prepared-source checkpoint

Architecture `2a4a8d70` precedes implementation `2875fa0e` and strict-style
refactor `8e60aa5d`. Eleven local real-filesystem/result/admission methods pass:
original capture, changed actual compiled input, changed archived bytes, symlink,
hardlink, retargeted path/archive, omitted role, first-manifest preservation,
strict complete actual-result refusal, genuine normal/optimized foreign-host
refusal before writes, and pending-integration refusal before any subprocess.
The result method covers boolean counts/status, failures, skips, expected failures,
nonzero exit, timeout/cancellation and forced cleanup. No native code executes in
these controls. Existing focus guard and owned-test supervisor controls also pass.

Both new Swift sources parse and pass pinned format/strict lint. Source compliance
passes with zero unverified tree items. Product/package/pins/licence/inventory/
notice/SBOM and every existing native lane are byte-identical to baseline main.
Source header review removed an unsupported XCUIApplication processID assumption:
actual NSRunningApplication PID/birth and unique bundle-process checks bind the
attachment before/after ordinary activation instead. No assertion was waived.

Execution remains explicitly held by `PENDING_ACTUAL_QUALIFIED_PREVIEW_MAIN`.
There is no new native outcome, Save-panel acceptance, merge, issue closure,
Apple-trusted cold launch or signed-artifact evidence from this preparation.
