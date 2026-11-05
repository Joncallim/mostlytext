# Recheck content ownership after token providers complete

## Owner outcome and baseline

A delayed syntax result must never apply old styles to a newer document. Issue19
explicitly retains this one-phase await boundary as an unresolved contract. The
current TokenSystemValidator checks a range's content version before calling its
provider but does not check it again before applying the result. A synchronous
provider can also reenter editing before returning. Reproduce both paths before
changing code; preserve unchanged-content and already-stale positive controls.

Merged main at intake isa52df48c1682f090c9816cf5faf8ecc790292da3. This source
unit starts from prepared lexer PR81 head03cba92ccc55107569bf8583b9e244770d9f5f23,
Neonab93bca8cc74af6f5e17eefc7fefa1999726a131, SwiftTreeSitter0beea992 and
runtime5ce80b6f. PR81 must pass/integrate first. Math probe PR82 is independent;
do not hold this correction for its native probe or silently reset its pin if
it merges first. Reconcile actual main and rerun the final combined source.

## Fixed ownership and implementation

Keep the actual Foundation-only TokenSystemValidator, Token, TokenProvider and
TextSystemInterface definitions. A controlled continuation suspends the provider;
change the content version before releasing it. Assert stale status and zero
style callbacks, not a timeout or a mock assertion that already discards results.
Use current, shrunk, grown and same-length content and both application actions.
Sync reentrancy must have its own failing-before proof before any sync change.

If reproduced, add only a version equality guard immediately after each affected
provider result and before applyStyles. Return the existing Validation.stale;
RangeValidator already handles obsolete completion. Do not change provider APIs,
validation scheduling, styles, semantic/paint geometry, buffers, cancellation,
parser/grammar or fallback. Preserve every earlier owner patch and original BSD.

## Verification and gates

Execute an inspected Foundation-only exact-source fixture; no AppKit/SwiftUI/
WebKit/product code runs locally. Verify exact production source hashes and run
Debug/Release, full owned component regressions and real test-target compilation.
Expose the same tests to actual Neon in hosted package CI. No sleeps, deadline
weakening, blanket suppression or versionless assertion is acceptable. If the
failure requires another owner/API/actor design, stop for a focused revision.

Pin the immutable owner child, update lock/inventory/notices/SBOM without other
pin changes, run316 Compliance/full format/strict lint, full hosted package/app/
CLI checks and exact-head review. Verify resulting merge tree and canonical
main. Update issue19's exact one-phase criterion only when that contract is
proved; original abort, mounted editor/lifecycle, native Release stress and
full-editor performance remain separate. Reassess all issues after each update.

## Reproduced result and compiler setup

Unmodified TokenSystemValidator reaches the style interface after every controlled
await/reentrant change:24 assertions fail over shrunk/grown/same-length content
and both actions. Unchanged and initially obsolete controls pass. The narrow
post-provider guards repair the exact failure;46 functions plus8 XCTest cases
pass Debug/Release, retaining all previous component regressions. No native UI
executes. A first compiler crash occurs lowering the generic default sync closure;
an explicit nil sync closure preserves the same provider contract and avoids the
compiler defect. Both that setup crash and actual failing baseline are retained;
compiler/language settings are not weakened. Current main is now verified
f87a414aff15577dd881cb80cad2928862b93839 (PR81 merged), reconciled into this branch.
