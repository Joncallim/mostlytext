# Diagnose the remaining mounted image copy failure

## Owner summary

The first complete qualification of the inline styling correction passed sixteen
of seventeen workflows. One original Debug Preview test copied plain fixture text
after a second image load. Prepare a private, single-case diagnostic to identify
where that image stopped between the admitted loader, Textual's attachment task,
and the visible native text layout. This is investigation only; it does not change
the product, relax the original five-second test, or qualify the shipping change.

## Baseline and observed failure

Current main is `a46c57c4b62376b67492cf67421a4961fdf55c1c`. The untouched
shipping candidate is `024103b3a0ce7d75025a5a14e7e0dacf9892973f`; its owned
Textual source is `ff74cf54c278b451b2c59387dd00315830266a36`. The exact
first Preview run is
[42450824327](https://github.com/Joncallim/mostlytext/actions/runs/42450824327).
The Debug revision pair's original initial suite had 55 of 56 tests pass. In
`aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration`, the first
native copy succeeded. The second load ID and byte reservation appeared, but
after five seconds the actual selected Textual layout held text `fixture` and no
attachment. A global trace recorded a 152-byte provider read, but did not bind
that read to the selected view instance. The five other Preview pairs passed.
Neither a framework scheduling cause nor a product code defect at a particular
layer is established by this first result.

## Question, scope, and data flow

The diagnostic asks whether the *same* second-generation Preview subtree:

1. received `image.png` as an image URL;
2. started its attachment task with the new load ID;
3. returned an image from its loader and passed cancellation/request-identity
   checks;
4. published an attributed value containing an attachment; and
5. reached the native interaction view whose current layout the original test
   copies.

The app test already knows the `resourceLoadID` passed by
`SecuredMarkdownResourceHost` to `TextualMarkdownPreview`. In the private
diagnostic branch, set a Textual environment value with that ID on exactly this
mounted test view. Textual `WithAttachments` reads it and emits structured log
lines containing the load ID, a model-instance ID and a per-task request ID.
Record only the image URL scheme and final component, run counts, attachment
counts, cancellation/request-identity outcomes, and lifecycle phase. The test
prints the expected first and second load IDs with its selected native view ID;
its existing failure-only layout readback remains the final visible result.
No document bytes, absolute paths, image bytes, new network authority or
persistent telemetry enter the trace.

## Boundaries and failure policy

The Textual diagnostic environment key exists only in an isolated fork worktree
descended from `ff74cf54`. It has no effect when unset. Instrumentation does not
change `.task(id:)`, child-task scheduling, attachment resolution, cancellation,
request-identity guards, published values, selection or copy behavior. The test
retains its source fixture, original assertions, five-second deadlines, and
failure status. It only adds phase/view/load-ID log lines and the environment
token. The existing `WithInlineStyle` shipping change remains byte-identical.

Use an isolated app worktree descended from `024103b3`. A diagnostic-only
version of the registered Preview workflow selects Debug/revision only and
requires manual dispatch. It does not replace the canonical six-pair workflow,
its checkers, or any original qualification record. Its first outcome and whole
logs/artifacts must be retained before any correction. If the targeted failure
does not recur, record that limitation; do not declare the original failure
repaired or retry unchanged source until it passes.

## Dependency and hosted execution plan

Do not hand-edit `Package.resolved` or run SwiftPM/product code in the owner
account. After source review, commit and publish the diagnostic Textual fork on
its own private branch, then run a guarded hosted macOS 26 ARM SwiftPM resolve
for exactly that fork revision. Capture old/new manifests, actual lockfile,
24-pin comparison, full logs, source restoration and host identity. Adopt only
the resulting verified lock in the private app branch, changing its Textual
manifest/project/inventory reference deliberately. Verify the other 23 pins,
notices and SBOM. Dispatch the one Debug/revision diagnostic only after these
inputs are immutable. This diagnostic evidence cannot be substituted for the
unchanged shipping candidate's failed first result or for a later complete
six-pair and 17-workflow qualification.

The guarded resolver ran once on the temporary resolve-only app branch
`cb6fea9783007a3b8189ed5904966d4b6ae231be`: [run 42485340067](https://github.com/Joncallim/mostlytext/actions/runs/42485340067),
attempt 1, succeeded on macOS 26.7.2 ARM with Xcode 26.0.1. Its actual
`swift package --package-path MacDown2/Packages/MacDownKit resolve` output
has manifest SHA-256 `eb35f5f6a0d46e25714b62bf07481d9635bb1643c3446f4a5537f46fcf6eb50b`
and lock SHA-256 `68c9c55f5b327596effa0f3086da1bf53229e3a22ccfddbda50bc3970cdde637`.
The other 23 pins were unchanged, the original manifest and lock were restored
on that temporary branch, and its first whole log and artifact are retained at
`/Volumes/Fast SSD/CORTANA-Builds/inline-attachment-instance-diagnostic-20261108/pin-resolution-first-cb6fea97`.
This resolves only the private diagnostic dependency graph; it is not a native
product result.

## Test and stop conditions

Before any hosted execution, review the source diff, Swift syntax, workflow
shape, actual branch ancestry and source-only inventory. Stop if the diagnostic
changes production decisions, a guard or deadline; broadens a permission; logs
absolute paths/document contents; or cannot correlate a Textual event with the
expected load ID. If the exact failure recurs, use the bounded trace to select
one narrower correction and preserve another complete first before testing it.
No issue is closed, no PR marked ready and no shipping branch changed on this
diagnostic alone.
