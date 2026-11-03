# Resume native safeguards and integrate the validated source history

## Owner outcome and authorization

On 3 November the owner asked to consume the Fast SSD test-account handoff,
resume integration without further intervention where possible, merge all
integration-final commits into the main application branch, then review/remediate
and close satisfied issues. The remote default branch is master; there is no
main branch. This instruction supersedes the earlier master freeze for code
integration. It does not authorize public releases or waive native/signing gates.

Integrated baseline is cf3f8b86; pending source baseline is #576 at 071b4bc3.
Preserve all existing worktrees, indexes, stashes, failure evidence and unmerged
branches. Merge through reviewed, validated PRs; verify the actual resulting tree.

## Handoff reconciliation

MOSTLYTEXT-OWNER-HANDOFF.md and native-completion-20261103 record genuine benign
test-account window/button and owner-data-denial controls, but zero product/UI
tests. The Fast SSD disables ownership; mode changes there cannot protect the
executor/products. The prepared /Library staging parent is absent. A nonprompting
administrator attempt refuses because authentication is required. The current
console is UID 501 with no active test desktop. Keep all actual account, product,
source, signature, GUI and execution gates. Do not alter drive/home/TCC policy or
run product tests in the owner's account to bypass them.

Bring the three reviewed local handoff commits (a75b32dc, e2690309, 6b9d57b2)
forward on the pending source. They bind the real CLI dependency and signed copy,
permit only canonical protected framework aliases, and provide one guarded focus
executor. Add non-launch controls for its terminal verdict and process bounds;
the unit controls are not positive native execution. Review external commands
for trusted absolute tool paths before lifting any hold.

Review found that the executor's original verdict ignored a recorded deadline
expiry: a zero exit after termination plus an already written one-pass summary
could be accepted. Factoring that exact condition and running the timeout
regression fails its actual assertion. The repaired verdict requires no timeout,
zero process exit and strict integer counts: exactly one passed, no failures,
skips or expected failures. Eight non-launch controls cover valid/missing/wrong
counts, malformed types and refusal of --execute under the owner UID. Normal
and optimized Python pass; no actual executor or product test runs. Existing
advisory/fixed controls pass 12 + 8. All 99 Compliance controls, inventory,
strict lint and pinned format pass. Actual protected staging/runtime remains
unverified and blocked by administrator authentication/test desktop.

## Hosted execution during capacity failure

Repeated macos-26 ARM jobs ran zero steps. GitHub's official hosted-runner and
runner-images references list both macos-26 and macos-26-intel as supported
macOS 26 hosts with Xcode 26. Add an explicit workflow_dispatch choice for the
two labels. Pull requests/push/default dispatch remain ARM. Every existing lint,
format, pinned package/app suite, Debug/Release app/mostlytext build, test-target
compile and lock check runs unchanged for either selection. Fail if the actual
host is not macOS 26 or no Xcode 26 is installed. Record architecture explicitly.
No older-OS fallback, skipped assertions, changed ceilings or release/native
acceptance is introduced. A complete Intel result is Intel source-integration
evidence; it does not claim ARM runtime or advertised-architecture release proof.

Primary references: [GitHub hosted-runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [macOS 26 GA announcement](https://github.com/actions/runner-images/issues/13739).
Local diff verification confirms every existing lint/format step and every step
from Install XcodeGen through final build/test/pin verification is byte-identical.
The host/toolchain preflight is stricter: macOS 26 and installed Xcode 26 are
required rather than selecting any Xcode when 26 is absent.

Use the exact dispatched head and complete raw logs to validate the combined
candidate before integration, then validate the integration-to-master merge.
Stale zero-step capacity failures remain visible. Executed test failures require
actual diagnosis/remediation and a fresh complete pass. Do not merge from only
partial checks or silently label unexecuted jobs successful.

## Review and issue closure

After the source merge, review the combined result through separate data-loss,
authority, async lifetime, parser/Unicode, packaging/CI and evidence lenses.
Repair concrete findings with discriminating controls. No independent reviewer
or final native acceptance is inferred from a scoped self-review. Update existing
canonical issues, check only completed criteria, close only complete contracts,
and retain precise residual native/artifact/language/external gates. Public
publication, signing keys and repository cutover remain separate actions.

## Hosted bookmark identity diagnosis

The first Intel full run executed all 3,302 tests but failed 22 unexpected
issues (plus two existing known issues); none of its later app checks ran.
Default ARM retries again ran zero steps: GitHub explicitly reports runner
acquisition failure and macOS arm64 capacity constraints. The stable integration
tree was separately transferred unchanged to master through #578, using its
complete successful ARM run 41462906779 and exact resulting-tree equality;
newer #570–#577 source remains held pending its own complete validation.

Private Foundation fixture probes on Intel (runs 41516548914 and 41516989441)
show six of six scoped bookmark operations fail in an unsigned executable with
NSCocoaErrorDomain 256, Failed to retrieve app-scope key. The same six operations
pass after ordinary ad-hoc signing. Adding an app-scope entitlement also passes,
but is unnecessary; do not add it or change production bookmark policy. All
unscoped controls pass. This isolates executable identity, not a production
permission or bookmark fallback defect. The diagnostic-only branch replaces its
CI workflow with a clearly named Foundation probe and is never integration CI.

For ordinary full CI, explicitly build the existing package test bundle and
ad-hoc sign/verify that ephemeral hosted executable before the unchanged full
swift test command. Verify the signature again afterwards. Keep package pins,
Debug configuration, complete test selection, all assertions/timeouts and all
subsequent app/CLI checks. No developer certificate, keychain change, entitlement
or product/release signing change is involved. The historical PR535 diagnostic
path stays unchanged. A fresh complete run is still required; signing probes do
not waive or establish the remaining renderer/performance/highlighting results.
