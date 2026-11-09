# Private Quick Look worker boundary: retained Finder failures

This branch tests a disposable hosted fixture, not the shipping Quick Look
extension. The real product, native test account and release acceptance remain
outside its scope. All three hosted five-test runs below failed; none qualifies
the per-request worker boundary or closes issue #7.

| Run and exact head | First native failure | Post-test verification |
| --- | --- | --- |
| [42537920687](https://github.com/Joncallim/mostlytext/actions/runs/42537920687), `a2874ba946635fd52708bf06c5365a0a9b1ea80d` | Four tests passed; the fifth raised while evaluating a `value CONTAINS` accessibility predicate against a numeric value. | The first Finder execution returned 65, so the host-observer proof could not qualify. |
| [42540219828](https://github.com/Joncallim/mostlytext/actions/runs/42540219828), `b5e12e6dd898ce853ae06e8a49e0c894c950202c` | Four tests passed; the fifth raised `Automation type mismatch: computed Other from legacy attributes vs StaticText from modern attribute` for an `AXHeading` at element 25 while enumerating `finder.staticTexts.allElementsBoundByIndex`. | The first Finder execution again returned 65. The `--verify-finder` step reached `validate_host_observer` and stopped because the UI supervisor was nonzero. Source, generated fixture, selected file, signed bundle and compiled-input equality checks preceding that point did not report a mismatch; verification did not complete. |
| [42553363963](https://github.com/Joncallim/mostlytext/actions/runs/42553363963), `3efd437d0dfd1d2270ee8663740cb1c0c5f1fa57` | Four tests passed; the fifth raised the same AX role mismatch while resolving element 9 from all descendants of the Quick Look window. Matching any role did not prevent XCTest from resolving the marker `AXHeading` again. | The first Finder execution returned 65; `--verify-finder` stopped at `validate_host_observer` on the nonzero UI supervisor. Its independent observer returned 0 with no errors, but no fifth result JSON or host-observer proof qualified. |

In the second and third runs, retained Finder accessibility trees show the
`MOSTLYTEXT_QL_WORKER_ISOLATION_OK` heading and a source line beginning
`# Hosted Quick Loo...`. The independent process journal records the held
worker PID 10243, normal worker PID 10247 and a normal-worker sample after the
held timeout. The fifth test failed before attaching its result JSON, so those
observations cannot replace its source, marker, timing and process assertions.
The receipt retains host-process and host-worker observations, but no
`host_observer_proof` or five-test qualification.

The next fixture-only correction keeps the marker query scoped to the Quick
Look window and reads the source text directly from its separate WebView Group
child, without enumerating the sibling `AXHeading`. It still requires the
exact marker, `# Hosted Quick Look fixture` source substring, normal worker alive after held
timeout, distinct workers in the same service, normal completion after the
held timeout, window retirement and no containing-app launch. The first two
failures and their result bundles must remain available when this correction
is reviewed or rerun.
