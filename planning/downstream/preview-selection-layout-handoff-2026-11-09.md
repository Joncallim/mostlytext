# Preview selection-layout handoff experiment

## Owner summary

The private Textual fork's view-bound `.task(id:)` handoff can leave the selected
native Copy model on an older layout after an image attachment is published. A
source-bound hosted run passed one ten-generation image sequence, then reproduced
the missing handoff in a control that should be independent of the one-line
mutation under test. This experiment will deliver the latest offered layout to
the same selected model outside the SwiftUI update frame, without relying on a
task tied to the lifetime of the clear overlay. It is a private feasibility
candidate, not a shipping Preview remedy.

## Exact observed boundary

- MostlyText private source `fd93b11e` pins Textual `e75d3a1`; hosted run
  [42525800028](https://github.com/Joncallim/mostlytext/actions/runs/42525800028)
  on macOS 26.7.2 passed all 56 selected initial app tests, the separate
  selection control, and ten source-bound image generations 3–12. The later
  revision-mutant selection failed 2/4 cases, so the whole run failed.
- The counterfactual changes only `PreviewResourceParsedFrame.revision` from
  `document.revision` to `0`; the compiled mutant executable differs and its
  source hash matches that single replacement. The intended parsed-revision
  case failed. The supposedly unaffected document-generation Copy case also
  failed at generation 8. That case retains one parsed document while advancing
  `FileDocument.mutationGeneration`, independently present in the host identity.
- For the failed generation, the resource loader read and decoded the new PNG,
  Textual published one attachment, and the selected native model was offered
  a one-attachment layout. No second `.task(id:)` `task-after` event reached that
  model. Its layout stayed at zero attachment runs and Copy returned
  `<p>fixture</p>`. The exact source and raw receipt are retained at
  `/Volumes/Fast SSD/CORTANA-Builds/preview-inline-instance-correlation-20261109/run-42525800028/`.
  The verifier correctly refused the incomplete mutant/restored comparison.

## Private change and invariants

1. Textual candidate `45d5ef2d` uses a per-`TextSelectionInteraction`
   reference object that receives each offered
   `TextLayoutCollection` synchronously but stores it without changing SwiftUI
   observed state. It schedules at most one main-queue delivery at a time.
   A newer offer replaces the pending one; the delivery uses the latest
   collection, model and coordinator for that modifier instance.
2. Delivery occurs outside the current SwiftUI update frame. It is not a
   `.task(id:)` attached to `Color.clear`, so an overlay redraw cannot cancel
   an otherwise valid offer. A monotonically increasing lifecycle epoch
   invalidates an old queued callback after disappearance. MostlyText's
   existing `content.id(resourceLoadID)` creates a new modifier for each
   resource/document generation, separating pending values across those
   boundaries. Model identity and diagnostic load ID are recorded before and
   after delivery in the private fork.
3. The production resource grant, document/source identities, Textual
   attachment loader and original mounted test assertions stay unchanged.
   No wider permission, network call, alternate renderer, timeout increase or
   forced success is allowed. The original unaffected controls remain required.
4. If a delivered one-attachment collection is still refused by
   `TextSelectionModel` equality, this experiment reports that as a separate
   failure. Do not force layout equality or weaken the model until that is
   observed and reviewed.

## Qualification before shipping consideration

- Four source tests control multiple offers in one frame, latest-wins delivery,
  reappearance, and disappearance before queued delivery. They prove the
  handoff object separately from SwiftUI timing; they do not prove native Copy.
- The private hosted app must bind the exact fork/app pins, compiled product,
  test source and raw results; pass the unchanged initial suite and selected
  Copy control, then pass the complete original four-case revision mutant and
  restored comparison with only the intended mutation failure. Repeat the
  ten-generation mounted sequence in independent fresh processes so a single
  lucky pass cannot mask the original race.
- Only after a diagnostic-free Textual/app candidate passes all six Preview
  consumer configurations, full CI, security and native release acceptance
  can shipping PR #146 or issue #13's first criterion be reconsidered.

The private source is a hypothesis. A passing component handoff test cannot
substitute for the original mounted image Copy, and an extra failed control
remains a failed qualification result.
