# Preserve the order of background syntax mutations

## Owner summary

A hosted package test on the PDF cancellation branch aborted while Neon completed
an editor-range mutation. The failure is separate from the original
SwiftTreeSitter out-of-snapshot abort in issue #19. A controlled Neon test
demonstrates that two edit requests can reach its serial worker in the opposite
order from their calls. The proposed fork change makes each deferred request
wait for the previous request's callback. This protects the range-state order
invariant while preserving the existing idle synchronous path.

This branch prepares a coherent dependency update for review. It does not
establish that the observed CI abort used this exact interleaving, resolve the
original issue #19 abort, meet issue #18's 1 MiB / 50 ms editor budget, or
qualify native editor behavior.

## Live baseline and ownership

The baseline is MostlyText `main` at
`ffe692feef9c7c8f45ccd2dea1f88e31115aeae6`. MacDownKit and the vendored
Markdown grammar currently select Neon `6074d1a5`, SwiftTreeSitter `76f93e7e`
and the transitive C runtime `3b1fb00f`. The original CI failure was
`RangeProcessor.swift:274` in PR #171's first full run; PR #171 changes no
package source or pins. Its earlier passing main run prevents classifying the
new failure as a known baseline outcome without further proof.

Neon owns deferred queue submission and callback order. MostlyText keeps the
exact dependency requirements, committed package lock, inventory, third-party
notices and software bill of materials consistent. No editor, export or preview
product code changes in this unit.

## Proposed source and dependency graph

- Neon fork PR #2 merged into its active branch as `f7023231`. The merge has
  the reviewed combined head `f729ff05` as its second parent and exactly that
  tree. The source commit `53134bfd` contains the two-file order correction
  and three focused tests, while the combined head incorporates the previously
  reviewed wrapper pin. A
  controlled old-source request hold produced callbacks `[1, 0]`; the changed
  source completed `[0, 1]`. The source path can reach the CI assertion, while
  the actual hosted interleaving remains unobserved.
- SwiftTreeSitter `7cf83c59` changes only its manifest, selecting the reviewed
  C runtime `1884982a`. The C fork corrects included-range lookahead and UTF-16
  decoder bounds/endian behavior. Its hosted C controls passed in run
  [42515686273](https://github.com/Joncallim/mostlytext/actions/runs/42515686273).
  The staged exact graph passed wrapper, Neon and MacDownKit package controls
  in [42520509316](https://github.com/Joncallim/mostlytext/actions/runs/42520509316)
  before the new Neon ordering source was added.
- The Neon BSD, SwiftTreeSitter BSD and C runtime MIT licence bytes were
  checked at these selected commits and match the existing distributed texts.
  Other package identities and requirements stay fixed.

The shared-subtree comparison probe previously allowed only the C files changed
by its own repair. It now checks the exact reviewed stages: `5ce80b6f` to
`3b1fb00f` changes only the package manifest and `subtree.c`, then
`3b1fb00f` to `1884982a` changes only `parser.c` and `unicode.h`. An arbitrary
runtime revision or a fifth product-source path fails before C execution. The
probe still compares all 324 ordered subtree results, requires the original
work-bound failure and candidate improvement, and runs the sanitizer phase.
The first [PR #180 hosted comparison](https://github.com/Joncallim/mostlytext/actions/runs/42544073176)
stopped at the older two-file guard before any C phase; that failed run remains
evidence. The revised guard retains the existing receipt's total-path list and
adds a separate stage record, so prior receipt readers keep their shape.

## Verification and stop conditions

Resolve the complete graph from the manifests and verify that exactly these
three lock revisions change. Run the full Neon suite with the new wrapper in
Debug and Release, focused MacDownKit range/highlight tests, strict formatting,
and the complete compliance check. Then run exact-head hosted package/app/CLI
CI and the relevant editor/highlighter selections. A source or performance
failure remains a failed gate; it cannot be repaired by raising a threshold or
marking the original crash as resolved. Preserve both the first failure and
the passing controlled old/new comparison.

This branch selects the immutable Neon fork merge, verifies its reviewed tree,
and recomputes the lock and compliance projections. Native mounted-editor
lifecycle and Release stress acceptance remain with the separate test-account
session and issue #19.
