# Invalidate embedded-language ownership after edits

## Owner outcome and baseline

Typing or replacing Markdown must expose the same inline syntax as a fresh
highlighter. Correct parser ranges alone are insufficient when the client still
considers old embedded-language work valid. This unit repairs the existing
client invalidation path, not the separate buffered-style coordinate problem.

Application branch baseline d826cc6ae3640f65cf075de9d863aafeebd4cc88 (PR77,
main5c867c5c at intake). Dependency baseline Neon526a29c48ff1b6e949aa47453f0861f9d7b14858,
SwiftTreeSitter7b914f4f1f91f3ecc60478136786babc6d6555fd, C runtime0.25.10.
PR77 must integrate first. Existing h5-neon-divergence evidence isolates missed
sublayer invalidation from buffer drift; inspect current actual source/tests
rather than transplanting old trace instrumentation. Owner approved targeted
fork remediation and implementation of the remaining-issue plan.

## Contract and interface

TreeSitterClient owns mutation/version and sublayer validity. Keep its public
API and threading unchanged. Every completed root edit invalidates embedded-
language ownership in the current transformed coordinates. Publish invalidation
state before calling external consumers that may synchronously query highlights.
Move existing mutation/version bookkeeping before synchronous parse completion
only if controlled callback tests demonstrate that ordering is required; retain
that evidence. Preserve generation and pending-mutation transforms.

Do not eagerly parse the entire document, change synchronous thresholds or
raise the8192-unit app fallback. Existing narrow validation may resolve needed
sublayers on query. Grammar admission, parser points, font styling, source bytes,
network/filesystem authority and native activation remain unchanged.

## Verification and slices

1. Construct strict Foundation/C-only TreeSitterClient tests using current
   Markdown grammars/queries. Warm the actual client so its prior sublayer set
   is valid, edit through willChangeContent/didChangeContent, then compare
   required-mode captures to a fresh client. Include ordinary and reentrant
   invalidation-handler queries, Unicode and LF/CRLF/CR.
2. Record failing old-source output with the same new tests. Apply only the
   reproduced invalidation/state-publication corrections. Run owned exact-source
   RangeState/TreeSitterClient component suites Debug and Release; copy only the
   pinned Foundation-only Rearrange sources, excluding its AppKit/UIKit helpers.
   No local Neon/AppKit/text-view/product execution is allowed.
3. Publish an exact-base owner Neon revision and update app lock, inventory,
   original BSD correspondence and notices/SBOM. No unrelated pin changes.
4. Host the real app/package/CLI build/tests and strengthen only the repaired
   existing replacement assertion. Remaining buffered-style/native/Release-wide
   failures stay visible; do not remove a known-issue wrapper on speculation.
5. Review exact head/merge tree and update owning issue evidence, then immediately
   audit all open contracts. No whole #6/#18/#19/#17 closure from component proof.

Source geometry, mixed synchronous/background edits and performance remain
measured separately. Existing Debug widened-edit abort is not declared fixed
from this client-only unit. All native EXCECUTION_HOLD prerequisites, strict
release failures, original failures and source/archive/app publication boundaries
remain intact.
