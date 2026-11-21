# Mounted viewport paint admission: bounded timing investigation

## Owner summary

The large Markdown editor still misses its 50 ms input-to-visible-bitmap target in some Release cases. The selected viewport lookup has already been made faster, but that did not remove the long delay. This investigation tests whether a paint of invalidated styling occupies the main actor while the short replacement parse waits to publish. It changes no user behavior or acceptance limit. A product change follows only if the exact timed phase supports a safe correction that preserves source, stale-paint protection and the independent full-parse oracle.

## Current baseline and hypothesis

Main `f11c75c549cf786972e2a372a84fd0f4501dd5e4` is the source baseline. [Mounted Release run 44941846897](https://github.com/Joncallim/mostlytext/actions/runs/44941846897) measured a 215.095 ms beginning-word input-to-bitmap result. Its local parse snapshot took 0.437 ms, while publication waited 204.223 ms to re-enter the main actor. Middle-word took 57.789 ms with a 0.372 ms parse and 39.872 ms actor wait. The timed loop does not run its independent oracle until a validation pass has occurred. These facts make an edit-triggered, pre-publication paint a plausible competing main-actor task, but they do not identify it as the cause.

`MarkdownViewportPainter.didEdit` schedules a refresh, and `MarkdownViewportSession.didEdit` also requests a pre-publication refresh to clear stale syntax. The session requests its local parse on a detached task. A refresh that spends tens or hundreds of milliseconds in TextKit invalidation/validation would explain the actor wait. The trial records the start and the three phase boundaries of each actual viewport paint without logging in the timed path, then emits the phase records after each existing bitmap readback. It keeps the input-to-bitmap stopwatch and all ten source/oracle/pixel cases unchanged.

If the long wait is occupied by a paint phase, evaluate a narrow admission or cleanup correction and prove stale styling cannot survive while a parse is pending. If not, remove the instrumentation from the merge path and retain the original failed timing. No diagnostic-only PR or issue closure follows from this probe alone. Protected native acceptance remains deferred.

## Result

The exact-head [hosted Release run](https://github.com/Joncallim/mostlytext/actions/runs/44953016394) passed its measurement workflow and retained all ten source, oracle and bitmap cases. The input-to-bitmap target still failed in middle-word (56.392 ms), Unicode replacement (67.085 ms) and replacement shrink (56.839 ms). Beginning-word happened to finish in 48.528 ms on this host; the earlier 215.095 ms failure remains valid evidence and is not erased by this run.

Each edit produced two viewport paints, before and after publication. For beginning-word they took 0.338 and 1.168 ms, while the local snapshot took 0.901 ms and publication waited 41.427 ms for the main actor. Middle-word paints took 0.583 and 0.482 ms; its local snapshot took 0.432 ms and actor wait was 41.366 ms. The phase durations reject the hypothesis that a slow paint itself accounts for the long publication wait. The wider main-actor scheduling cause remains unknown. Do not remove the pre-publication stale-paint guard, merge this instrumentation, or claim the 50 ms criterion passed. A future investigation requires a new time-aligned lead; the protected native checkpoint remains deferred.
