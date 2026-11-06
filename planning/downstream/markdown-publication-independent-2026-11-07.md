# Integrate the qualified Markdown publication guard independently

## Owner summary

A cancelled or superseded immediate Markdown parse must not publish older
content into the active session. PR107 already implements and qualifies this
bounded correction. It can integrate without the separate production Preview
activation whose native Copy failures hold PR108. Preserve the exact reviewed
production and fixture code, rerun the actual current-source gates and merge
only after their complete results. This is not a waiver of Preview failures.

## Current baseline and architecture

Main c3e9fd066277b29e653a01045d6ad24e5e1fb1e6 and PR107 head
75ff4ef9b6c074cddb900e355d78c55b1957ee26 share d607098b as ancestor. Every
MacDown2 and native-orchestration input on current main still matches that
ancestor; intervening D2 evidence, packaging and documentation commits do not
change these product inputs. Read the existing Markdown publication architecture
and retained old-source failures, plus root EPIC_STANDARD/RELEASE_HARDENING.
The computed integration is conflict-free. Preserve PR107 as a merge parent,
not a rewritten historical head or a retargeted receipt.

The existing contract remains: MarkdownParseSession owns its generation, checks
cancellation AND current generation after the awaited parser returns, and counts
physical work until that await actually ends. No public API, debounce/busy/
equal-options policy, parser worker, pin, renderer or resource authority changes.
Keep the original deterministic four busy-state tests, add the actual gated
publication regressions and retain all before/after source console evidence.
The reviewed optional initialContentController keeps normal WindowController's
real workspace by default; direct native math/heading adapter fixtures explicitly
own their parser instead of starting a competing workspace producer. Preserve
the real model, controller, native editor and window; no result injection.

## Sequence and stop conditions

Write this current-main contract before merging the reviewed PR107 source.
Verify every MacDown2 blob and required workflow/script blob in the resulting
candidate is byte-identical to the previously qualified75ff input. Retain all
historical native/console failures and explanations at their original SHAs.
Run current ordinary332 compliance/inventory/strict formatting and lint, complete
normal locked CI and fresh Debug/Release native math29/9 plus heading68/9 checks
on this complete source. Actual receipts must bind full current source keysets,
all24pins, real selected execution and owned statuses. No local native execution.
Any new failure blocks this source's merge; no unchanged retry, deadline change,
skipped control or altered acceptance criterion. A correct computed tree and
identical reviewed source do not substitute for the required fresh execution.

After green exact-source checks and review, verify synthetic/computed/source
merge trees, merge with the expected-head guard, audit all open issues and verify
actual parents/tree and clean canonical fast-forward. Only then close PR107 as
integrated by ancestry, with exact merge/evidence links. PR108/100/101/106 remain
held until their independent or corrected combined prerequisites pass. Original
owner/signed/native release gates and whole-issue closure criteria stay open.
