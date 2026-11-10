# Preview Copy selection-layout handoff candidate

The first exact PR #146 native Preview qualification remains failed at source
`024103b3`: Debug revision Copy lost the inline image on its second document
generation. It is not replaced by later diagnostic evidence.

A private same-checkout A/B workflow at `d5934f85` compared the prior Textual
selection handoff `d2f84884` with an instrumented coalesced handoff
`45d5ef2d`. Each arm compiled its own real app and test bundle, selected all
four mounted tests, and ran ten fresh native executions with ten image
generations in each mounted Copy case. The [old arm](https://github.com/Joncallim/mostlytext/actions/runs/42637265480)
failed two of ten repeats; repeat 1's generation 11 had a decoded image but its
selected model was never offered the attachment layout before Copy, producing
plain `fixture` HTML. The other failure was a fresh-model image Copy refusal.
The new arm passed ten of ten repeats, with 4/4 tests and ten generation
correlations in each. Raw XCResults, event logs, source maps, compiled hashes,
and the failed first are retained in that workflow's artifacts. This is a
controlled diagnostic, not a production qualification or proof of a sole OS
cause.

Clean Textual child `4bc5a45e384b596e0c1448888c8534a6df436c57` is based
on the shipping `ff74cf54` pin. It contains the main-actor latest-layout
handoff, four pure tests and the manifest's missing SwiftUI Math lock entry;
no diagnostic logging enters the child. The four pure tests pass locally, the
Swift source parses, and the fork's original MIT LICENSE remains byte-identical
to the captured text (`9c9191ada6888f3da1a888b6c74dae46e98787b1150c734e3b1e5ec5bbf73b09`).
[Textual PR #1](https://github.com/Joncallim/textual/pull/1) isolates this
child against the current shipping fork branch. GitHub reports no registered
Actions workflows for that fork despite the workflow files and enabled Actions
permission; an exact-app guarded hosted run is still required.

This private integration checkout combines MostlyText main `d14c4b3d` and the
PR #146 source with that clean Textual pin. SwiftPM locked dependency readback
resolves to `4bc5a45e`; the `Preview` product builds locally, and the
compliance tree check passes with zero unverified items after inventory, notices
and SBOM regeneration. It has not run the app on the owner desktop. The next
gate is an exact-head hosted six-pair Preview run including Debug revision,
then the full current-head matrix. Installed native and signed-artifact
acceptance remain separate.
