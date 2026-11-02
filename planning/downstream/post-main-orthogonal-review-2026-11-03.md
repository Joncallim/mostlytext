# Post-main source review and integration convergence

## Owner outcome and scope

The owner requested the Fast SSD test-account handoff, completion of all work
possible without intervention, transfer of integration-final history to the main
branch, then a deep review/remediation and issue reconciliation. The repository's
main application branch is master. PR #578 transferred all 178 integration
commits from cf3f8b86 onto master 87d8d48b, preserving history. Its resulting tree
8fa4c421 matches the complete successful ARM validation run 41462906779 exactly;
fresh Compliance passed. Queued fresh CI was not represented as a new pass.

This source review uses separate data-preservation, authority, async-lifetime,
parser/Unicode, CLI/packaging and evidence lenses. It extends the prior #183
source passes; it does not invent an independent reviewer or qualify an exact
native/release artifact. The candidate combines the pending #570–#577 stack,
#579 save retirement and #580 physical parser ownership so full CI can evaluate
their interactions. Every source history remains reachable. Merge only a complete
validated combined result; reconcile ancestor PRs without relabeling their own
failed/zero-step checks as successful.

## Findings and dispositions

| Lens | Evidence and disposition | Remaining boundary |
| --- | --- | --- |
| Failed-save preservation | FileStore's blind temporary cleanup deleted changed/replaced files in four real controls on exact merged FileCore sources. #579 uses exclusive stages, known-byte/object receipts and bounded no-follow quarantine/restore. Original four failures retained. | Same-UID adversarial filesystem compare-and-swap and crash scavenging are not claimed. |
| Accepted-save retirement | A second controlled hook after displaced-baseline verification reproduced two cases that both deleted competing bytes and falsely reported success. #579 binds the approved baseline to a streamed receipt and reuses the same quarantine/restore mechanism. Four failing assertions retained. | Original rollback, FAT32 fallback, ACL/xattr and encoding policies stay covered. |
| Physical async lifetime | ParseEngine's actor reentered while a large-stack thread ran. Actual controls reached physical peak two, even with owner cancellation; canceled queued work started. Nine failures retained. #580 retains the per-engine slot until physical completion, removes canceled waiters and preserves FIFO handoff. | No global worker pool, forced cmark/Yams interruption, #203/tree-sitter fix or native preview budget is inferred. |
| Native execution verdict | Pending #577's original executor could accept a recorded timeout after a zero exit and one-pass summary. The actual negative fails before the strict repaired verdict; 28 non-launch Python controls pass. Absolute system tool paths are pinned. | Protected staging, signatures, exact candidate, positive control and test desktop remain actual execution gates. |
| Hosted executable identity | Intel's unsigned Foundation fixture fails all six scoped operations with app-scope-key error 256; ordinary ad-hoc signing passes all six, with no entitlement. #577 signs/verifies the ephemeral package test host and retains the original complete test command and assertions. | A signing probe is not complete CI; remaining timing/highlighting results must pass a fresh full run. |
| Source/parser binding | Pending #570/#576 freeze one exact parse and bind full input bytes, revision/options and heading anchors. This review combines those changes with physical admission and reruns the exact combined parser source corpus. | Runtime in-app/Export TOC navigation remains #117 native acceptance. |

## Cross-boundary readback

- CLI stdin keeps one caller-owned descriptor, exact UTF-8 bytes, bounded
  admission/deadlines and restores original flags. Command startup waits for
  launch restoration; production CLI naming/copy binding remains mostlytext.
  No new defect was established in the reviewed transport/startup paths.
- Migration journal storage checks owner/mode/ACL/type and live directory/lock
  identity, writes through exclusive no-follow descriptors, syncs file/directory
  and never deletes named stages. Its partial-initialization close is idempotent.
  The new save-stage helper separately keeps descriptor closure with its actual
  initialized lifetime; it does not reuse journal authority.
- FileTree Trash confirmation freezes the originating model, root generation,
  source URL and window-liveness check. Pending #574 preserves that authority
  through confirmation, rather than acquiring a later window/root's context.
- JSON immediate analysis keeps physical busy counts separate from publication
  generations. Canceling/superseding publication does not falsely report an
  already-running immediate worker as idle. Native geometry/highlighting cases
  remain in #459/#203; the parser worker fix is not their closure.
- The legacy HTMLPreviewView still routes to PreviewSchemeHandler. Its known
  path-check/reopen and synchronous-read limitations remain explicit #121 debt.
  The bounded grant/handler consumer is implemented but inactive, as specified
  by issue-121-directory-grant-proposal.md's native/containment activation gate.
  This review does not mistake the inactive implementation for production
  activation or bypass that gate while the test desktop is unavailable.
- Licensing inventory/locks and retained release/native boundaries are checked
  independently of source integration. No signing key, release publication,
  source offer or repository cutover is authorized by a code merge.

## Verification and evidence discipline

The exact post-main baseline harness contains all 54 merged FileCore/JSONSupport
source/resources and reproduces the first four failures. Repaired FileCore passes
135 source tests / 18 suites in Debug and Release. Master-based MarkdownEngine
passes 129 tests / 18 suites in Debug and Release after its nine-assertion
negative. Combined source harnesses are regenerated from this candidate, without
adapters, and bind hashes for every copied file; their summaries are recorded in
the external run ledger. The original app/CLI import-only receipt harness and
all earlier negative controls remain preserved rather than rewritten.

Initial failures remain inspectable: missed shared fixture support, stale tests
from the separate anchor candidate, generated-project inputs after rebasing,
strict-lint findings and eleven modification-date rounding issues in the first
displaced receipt implementation. Fixes preserve assertions; no tolerance,
timeout ceiling or unsupported security fallback is used to obtain a pass.

Full hosted package/app tests, Debug/Release app and mostlytext builds, test-target
compilation, strict lint/pinned format, Compliance and package-pin verification
are required for the combined source merge. Keep original Intel's 22 unexpected
issues and all explicit ARM acquisition/capacity failures alongside later results.
A fresh complete pass supersedes a diagnosed failure; it does not erase it.

## Issue and branch reconciliation

The live post-main audit records 17 open canonical issues. Source improvements
check off only their own completed criteria; entire issues close only when their
complete contracts are evidenced. Native UI/WebKit/Quick Look/VoiceOver, release
artifact, language and external-access criteria remain distinct. #115 consumes
source integration as progress, never native/release completion.

Merged branch cleanup retains master/integration-final/default refs, every
unmerged branch, worktree directory, index, stash and recovery bundle. A branch
whose HEAD happens to equal merged master while active uncommitted work exists
is not eligible for deletion. Reaudit after final integration; never remove a
worktree directory or reset its files as branch housekeeping.

## Hosted test-host sequencing correction

The full signed-host rerun 41518126997 still failed: raw logs prove that SwiftPM
linked MacDownKitPackageTests again between ad-hoc signing and test execution.
It therefore discarded the identity just established by the fixture probes.
All 3,302 tests executed; 20 unexpected issues and two existing known issues
remain retained. Do not claim the bundle signing alone fixed the full suite.

Explicitly build every test target, sign/verify the host, then use swift test
--skip-build --no-parallel --force-resolved-versions to execute that exact built
suite. The installed tool help confirms --skip-build skips compilation, not
selection or execution. Hash the executable before/after and verify its signature
again after a pass. No test filter, disabled assertion, budget change or new
entitlement is introduced. The obsolete first combined run is explicitly
superseded for this diagnosed sequencing error, not counted as a pass.

## Actual Swift Testing host identity

Full run 41521890558 executed 3,311 package tests / 460 suites and retained 23
unexpected issues plus the two existing known issues. Its 17 bookmark assertion
failures persisted despite signing the bundle and preventing relinking. A
minimal package probe at the same Xcode 26.0.1/Swift 6.2 toolchain identifies the
actual process as the installed swiftpm-testing-helper. Signing the loaded
bundle cannot establish that executable's identity; disabling XCTest still uses
the same helper and does not create a standalone executable on Darwin.

The official Swift Testing command-line debugging reference documents invoking
this helper with --test-bundle-path and --testing-library swift-testing. Use a
byte-verified private copy of the exact selected Xcode helper, ad-hoc sign and
verify that copy, and provide the same Xcode platform's Testing.framework search
path. Never modify the installed helper or Xcode. Do not distribute the copied
vendor executable as a product or workflow artifact. The matched private-helper
probe 41528703799 passes the actual scoped-bookmark assertion; the original and
bundle-signed paths both fail. An explicit failing-assertion exit control is
also required before using this path for full CI.

Normal full CI retains all framework tests: the ordinary pinned SwiftPM command
executes XCTest with Swift Testing disabled, then the owned helper executes the
entire Swift Testing bundle serially with no filter. Current package sources
contain no XCTest import or XCTestCase subclass, matching the original zero
XCTest count; retaining that pathway also avoids dropping future framework
coverage. Hash the test bundle and helper around execution, preserve every
assertion/budget and require complete actual summaries. This is infrastructure
identity, not a production bookmark permission change or native acceptance.

Reference: [Swift Testing command-line debugging](https://github.com/swiftlang/swift-testing/blob/main/Documentation/CommandlineDebugging.md).

The final minimal package control 41529393284 confirms both sides: the matched,
owned helper executes the actual scoped-bookmark test and exits zero; a separate
intentional assertion failure executes one test and exits one. Default,
bundle-signed and XCTest-disabled original-helper paths all retain their scope
failure. The normal CI path now uses that proven helper strategy, preserves the
original helper/bundle bytes with before/after hashes, and retains XCTest plus
the full serial Swift Testing execution. No toolchain binary is modified.

## Editing scan and fixture fidelity review

The candidate also incorporates #582: prefix admission avoids redundant full-line
scans while preserving all existing UTF-16 helpers and fence grammar. All 165
Foundation-only controls / 16 suites pass Debug/Release with an explicit pure
transaction-DTO extraction; 17,376 generated caret classifications match the
previous source. Complete pure Smart Home on exactly 2,000,000 units falls from
about 47.70 to 23.33 ms in Debug; the existing named 1 MB fixture is actually
475,008 ASCII units and its pure newline decision falls from about 3.55 to
1.59 ms. Those numbers do not establish a full-size/native budget. Fixture
fidelity remains in #112/#203/#115. The native backing-store getter probe shows
no material getter cost, so no speculative getter change is included.
