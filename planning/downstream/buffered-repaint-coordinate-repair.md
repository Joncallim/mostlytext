# Preserve pending repaint ranges across later edits

## Owner outcome and current baseline

Several edits in one turn must repaint the same source that a fresh highlighter
would style. The buffer currently unions dirty ranges in the coordinates in
which each callback arrived. A later edit can move or delete that source before
the buffer flushes, leaving the wrong region dirty.

Application baseline 377af67b675e52cbefe280a2531f5a1d9264de99 (PR #78), pending
PR #77 and #78 integration; live main remains 5c867c5c at intake. Neon baseline
0699ea559682b4f62c8cd10ae520c7262c4acaa9 contains the separately tested client
repair. The old h5 divergence evidence and current TextViewHighlighter callback
order confirm this is a separate remaining defect. This unit changes buffered
geometry only; it does not activate the widened edit experiment or native tests.

## Ownership, interface and state transitions

RangeInvalidationBuffer owns a package-only contentChanged(in:delta:) hook. Its
range refers to the original text replaced by this edit. TextViewHighlighter
calls it after computing that original range and before client.didChangeContent
can publish invalidations for the new text. The styler keeps its existing edit
notification and flush scheduling. No new public API or dependency is required.

Idle buffers have no retained coordinates to transform. Buffering depth remains
unchanged. An all-document invalidation remains all. For explicit sets, retain
dirty source strictly before the edit, shift surviving source after the old edit
end by delta, and discard deleted indices. If an edit touches a dirty range,
conservatively include its replacement text; an insertion inside a dirty range
includes the inserted span. Newly published invalidations already refer to the
new text and are unioned only after that transformation.

Use a linear sweep of IndexSet intervals. Do not enumerate source characters or
use the generic NSRange.apply operation: it drops surviving dirty tails when a
deletion overlaps the beginning of an interval. Keep this correction local to
buffered invalidation; other Rearrange transformation semantics are not changed.

The buffer still leaves the old scope before invoking a flush handler. Nested
scopes and handler reentrancy must preserve their existing behavior. All methods
retain their current executor confinement; no worker or scheduling policy changes.
The hook receives the same valid TextKit edit range/delta already passed to the
client and styler. Invalid geometry remains a programming error, not a fallback
that silently repaints the document. No source bytes or owner data are rewritten.

## Verification and slices

1. Add Foundation-only interval/character-identity oracle tests for insertions,
   deletions, replacement, dirty-tail survival, repeated edits, nested depth,
   all-document state, idle state and reentrant scopes. Original class plus an
   explicitly labeled no-op notification shim models the missing old hook; its
   failures establish the geometry counterexample, not native execution.
2. Implement the narrow buffer hook and callback ordering. Verify exhaustive
   small geometry against an independent per-character dirty-state oracle and a
   long sparse-set case without a timing claim. Run all exact-source RangeState
   and TreeSitterClient component tests Debug/Release in the vetted Foundation/C
   fixture. Preserve the original reentrancy and client tests.
3. Publish an exact owner fork child and update the app pin, original BSD notice,
   inventory and SBOM with no unrelated dependency changes. Strengthen the app's
   typing-then-deletion assertion; full hosted CI must prove the actual adapter.
4. Review exact head, merge only after predecessor integration and full hosted
   checks, then update #18/#19/#17 evidence and immediately audit every open issue.

## Completion and residual limits

The required outcome is correct buffer coordinates plus the existing real
highlighter regression passing strictly. The 8192-unit fallback, parser budgets,
root grammar, styling APIs, widened Debug abort and native execution hold remain.
Component results do not establish whole-editor latency or native accessibility,
Quick Look, exports, signing or release acceptance. Existing release-only rights
and source-publication blockers remain recorded. No upstream outreach is needed.

## Hosted review reconciliation

Initial CI41969776856 at2dc95c3e passes both strict selection replacement and
combined typing/deletion controls but fails the existing below-cutoff style
comparison. The same failure appears in PR #78 before buffer changes. The
actual warmed-client/partial-adapter test isolates complete captures repainting
outside their query authority. Carry the exact e528a19 correction through owner
Neon merge9db7e1d, preserving this buffer implementation and its independent
oracle. The merged component suites pass39 functions in10 suites plus8 existing
XCTest cases Debug/Release. Retain both first hosted failures, selected prefix
provenance and new receipts; require fresh full CI for the corrected app head.

## Preserve semantic capture identity in the final style path

The second hosted run41972235335 at7c3f40ba passes the visual controls but fails
two existing mounted byte-geometry checks: clipping the Token changed what an
attribute provider observes. Carry owner client6797068 through merge baf93c7.
It restores complete semantic tokens and intersects a separate paint range via
a package-only iterator used by all three concrete interfaces. The buffer hook
and its independent oracle remain unchanged. Preserve both rejected hosted
heads and require new full checks, including unchanged geometry and visual tests.
The outside-query property remains active using actual TextStorageSystemInterface
on hosted builds and the exact iterator/memory styles in the local pure fixture.
