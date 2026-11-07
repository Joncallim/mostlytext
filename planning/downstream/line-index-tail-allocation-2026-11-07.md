# Reserve the final line-index allocation before copying its tail

## Owner summary and baseline

Reduce temporary allocation/copy work during an edit without changing text,
line coordinates, layout, parser behaviour or the public editor interface.
Current main is427d15fa5da94d4045a02e7f6a005648d09e38c5. Its EditorLineIndex,
coordinator and existing10MBkeystroke fixture are byte-identical to failed
Preview candidatefc29. That candidate's first Debug theme run42376176031 executes
all1087functions and fails one original50ms10MBincremental-keystroke assertion at
62.876833ms. Release1087/145 passes. This is not issue18's1MBwhole-editRelease proof.

Source inspection establishes a separate avoidable allocation cost: applying an
edit builds a new offsets array from its prefix, appends rescanned offsets and
then individually appends every unchanged tail offset. It already knows all
three output counts but leaves the potentially large tail to repeated capacity
growth. Do not claim that this cost alone caused the observed62.88ms failure.

## Scope and invariants

One implementation change in EditorLineIndex.applying: reserve the exact final
prefix + rescanned + remaining-tail count after the existing boundary-duplicate
removal and before either append. Keep every scan boundary, CR/LF/CRLF treatment,
UTF16 coordinate, margin, shifted offset, stored count and publication unchanged.
Do not add a tree/piece representation, cache, global state, unsafe buffer,
conditional benchmark path, product flag or new dependency. The unchanged tail
still takes linear work; this does not make a whole edit constant time.

The final output storage is required regardless of this reservation. Reserving
it explicitly avoids capacity growth and intermediate copying; no filesystem,
network, normalization or authority behaviour changes. Failure semantics remain
ordinary allocation failure rather than silent truncation or a reduced fixture.

## Validation and completion

Existing line-index boundary/Unicode/mixed-EOL/fuzz and editing/IME suites provide
behavioural regressions. Keep them byte-identical; do not add a test that simply
asserts the new allocation call. Source/style/compliance and scope checks run
locally, with no product/framework runtime. Full hosted package/app tests and
four locked builds must pass. Both complete theme selections preserve all1087
functions, original bitmap counterexamples, orientation proof and unchanged
50mskeystroke limits. Retain each first result before a material correction.

Record actual new timing only to the extent observed. A passing new selection is
not a sole-cause explanation of an intermittent old failure or a waiver of
fc29's failed qualification. This allocation unit may integrate independently
against actual qualified main if its own complete required checks and source/tree
review pass; Preview's separate initial-copy failure remains unresolved and its
candidate stays unmerged. Issue18's whole-path budget and original Debug abort,
installed/signing/owner/final-artifact requirements stay open.

A native failure stops this unit's readiness. No unchanged native retry, increased
budget, skip, expected failure, changed fixture/delegate or compiler optimization
switch is authorized by this architecture.

## Actual qualified-main intake before publication

PR133 is now merged at actual main56725f941f3ee8f23b6255432c229226eff8e63f,
parents427d15fa+4c4e98ff and exact reviewed/native-tested treecd4ffbb2. Its ordinary
Release stdin/native Save As first result independently verifies49physicalUTF8bytes
before/after normal same-process Quit,1613public+7private inputs,24pins,13generated
files and10downloaded compiled roles. Its genuine input control and native case
both pass; main's product/package/compliance bytes remain identical to427.

Take actual main567 into this allocation branch before first publication. Against
that actual main, the runtime delta stays exactly the three capacity-reservation
lines; existing tests, payloads, compiler settings, workflow helpers and bounds
remain unchanged. Native qualification has not run for this allocation source.
No local Foundation/product/AppKit benchmark or runtime is used; all timing and
behaviour claims await complete hosted first outcomes.
