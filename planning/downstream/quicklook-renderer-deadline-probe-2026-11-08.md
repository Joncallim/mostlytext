# Measure real renderer work and fallback delivery in a hosted Quick Look provider

## Owner outcome and live baseline

Current main is52652b07ff2d3b953e137e82836b544bdfb79786. PR138 proves that closing
Finder's Quick Look window does not cancel the private cooperative provider on
the observed macOS26 run. A production extension therefore needs a real bounded
reply policy; async syntax alone cannot supply it. Before shared presentation or
production integration, test whether the chosen provider executor can return
its already prepared safe fallback while an actual D2 renderer is outstanding.
This is a named platform-feasibility slice of the binding E23 handoff, not a new
renderer or production target. It does not clear all QL-REPLY or #7 acceptance.

## Scope and authority

Use a separate .github/quicklook-deadline-probe fixture on one real guarded
hosted macOS26 ARM64 runner. Reuse the exact original cold-Finder case as the
positive control, the separately targeted automation host, exact sandbox plus
user-selected-read-only provider permissions and the guarded live-log admission
channel. No local product/app/extension builds or GUI, owner data, Developer ID,
notarization, TCC/default-handler/AppGroup/network permission change. Register
only the reserved private Markdown provider on its ephemeral runner.

The private XcodeGen provider links the actual current D2Rendering product from
MacDownKit at its unchanged committed source and24locked pins. The existing
renderer/harness/WASM/fonts/pool remain byte-identical to main. Capture all
runtime provider/containing app/test bundles and their resources, not only Mach-O
files; record every source/generated/compiled input and actual package pins.
Source compliance must remain green; no new third-party code/dependency is added.

## Request ownership and result policy

Prepare tiny immutable safe HTML/source fallback before work admission. Each
request has an independent thread-safe terminal gate and one continuation,
separate from a renderer occupancy lease. The provider callback waits for a
Sendable result payload; it constructs the actual QLPreviewReply only after that
result arrives. The synchronous factory returns frozen bytes only. It cannot
perform rendering, file access or await an actor.

Use one absolute two-second optional deadline from callback admission. A
background controller may select fallback without awaiting a still-outstanding
renderer task. A late result cannot replace a delivered fallback or resume the
continuation twice. Do not use a TaskGroup whose scope waits for an uncooperative
child. Keep one renderer occupancy charged until its actual render API returns,
including its existing cleanup, and refuse another rich admission while busy.
API return is not proof that framework WebContent memory/processes have exited;
retain that distinction in evidence. No silent slot refund on deadline/closure.

The real renderer uses unchanged D2WebRenderer limits (pool1, existing5second
execution/15second admission and2MiB output bounds). A generated valid small
D2 diagram provides a real render-positive control; a separately generated
large valid graph attempts to keep actual renderer work outstanding past the
provider's two-second deadline. No inserted sleep, mocked renderer, held fake
completion or synthetic busy loop qualifies the real-work predicate. If the
large graph finishes early or the real renderer never actually starts, retain a
negative/inconclusive feasibility result; do not pad native waits, claim a slow
worker or re-run unchanged. Worker start/terminal/deadline/publication events
carry one request ID and monotonic timestamps, with no authored/private content.

## Actual Finder journeys and discrimination

1. Execute the unchanged original cold-Finder static marker/image positive.
2. Select the generated small D2 file in real Finder and invoke Space. Require
   the actual unique rich-success marker and a nonempty actual rendered output;
   a fallback/error is not the rich control. Record raw screenshot/AX/logs.
3. After its real worker drains, select the generated large D2 file, invoke
   Space, and require the safe fallback marker while the real worker is still
   outstanding. The raw logs must order callback < real worker start < deadline
   <= fallback reply/factory < real worker terminal. The two-second controller
   deadline is measured independently of the larger unchanged UI observation
   allowance. Close through actual Escape; no Task.cancel substitution.
4. Preserve actual immutable fallback bytes/factory counts and verify only one
   terminal selection. Retain a directly invoked negative gate/counterexample
   in separate controls; a failed native positive remains a failure, not waived
   by direct control tests. Subsequent requests are independent; busy admission
   cannot silently replace or cancel an earlier request.

## Verification and stop conditions

Before the first hosted publication: review current real renderer interfaces,
source/SDK type-check where possible (no local linked package build), run pure
schema/correlation/corruption/ownership controls, format/strict lint/diff/YAML
and source compliance. Freeze one source and preserve complete FIRST native and
Compliance outcomes/logs/artifacts before any material correction. Independently
read raw XCTest summary/attachments, actual permissions/pins/compiled resources,
provider logs and own process lifecycle. A forced cleanup, missing callback,
wrong request/ordering, double terminal or changed input fails qualification.

A successful narrow result establishes fallback delivery during actual work;
it does not establish all renderer performance/calibration, WebContent process
memory/retirement, system factory repetition, hostile passive composition,
production extension packaging, final install/localisation or whole QL-REPLY.
Any false execution-placement assumption requires a written narrow architecture
revision before more code. The production app/packages/project stay unchanged.

### Real API observation boundary before implementation

The current D2 renderer exposes no public worker-phase hook. The probe's actual
worker-start event therefore brackets invocation of its unchanged real render
API, not entry into WASM or proof of a physically blocked MainActor. A successful
small diagram must still return real valid SVG. The large-case ordering can
establish fallback while that real API is outstanding, including real renderer
preparation/admission/execution, but cannot identify its internal pending phase.
Do not claim that narrower result proves synchronous WASM interruption, hard
memory bounds, physical WebContent retirement or the complete QL-REPLY gate.
No production or copied-renderer instrumentation is added to manufacture a
worker-phase observation. Preserve a result that lacks the required ordering as
inconclusive/failed; do not silently relabel it as actual busy WASM evidence.
