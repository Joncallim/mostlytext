# Downstream architecture — implementation entry point

> Current reading guide — 3 November 2026: initial baseline and “current” source
> observations in the dated architecture below describe their original snapshots.
> Later merged source/identity/notice changes are summarized in
> [acceptance status](../ACCEPTANCE_STATUS.md) and [remaining engineering](../ENGINEERING_REMAINDER.md).
> Source integration does not establish native acceptance. Quick Look's QL-REPLY
> feasibility probe, held preview/current-line activation and other named native
> prerequisites remain binding; a documentation update does not skip them.


Current review: **26 September 2026**, restored master `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`.
Current PR: **#147**, branch `docs/downstream-architecture-2026-09-24`.
Original architecture: **#125**, preserved at `b2c6d19ef453b571f4eb5eb020accfa84305fb60`.

## Start here without interrupting E22

Continue current Epic 22 under its existing implementation plan. This documentation work does not change Claude's source, active branches, E22 plan, design lane or workflows. The later parser-option portion of #53 and command-registry portion of #117 remain with E22; consume their completed outcomes instead of implementing them again.

#125 was accidentally closed during the repository reset, not rejected. GitHub refused reopening it even after restoring common branch ancestry. #147 is the linked replacement, preserving the original commits plus restored master, without force-push or master modification. Do not keep trying to merge the closed #125 or resurrect its old source baseline over new implementation.

Before downstream code, read [READINESS_REVIEW.md](READINESS_REVIEW.md), [RELEASE_SEQUENCE.md](../RELEASE_SEQUENCE.md), and the applicable hand-off below. Adopt the documentation through the normal PR process, reconcile exact post-E22 master and actual issue/design decisions, then implement dependency-ready units. The dated baseline is not a claim that master will stand still.

The renewed review covers all **13 downstream issues**. Nine hand-offs were revised in place; four retained their design, with explicit clarifications in the review record. Two additional focused continuation passes strengthened prerequisite enforcement and retained-resource ownership. Each issue still needs actual implementation/acceptance evidence. Proposed numerical limits are design ceilings to validate, not measured performance passes.

## Issue hand-offs

| Issue | Implementation contract |
| --- | --- |
| #121 | [Immutable HTML preview loads and contained resource reads](issue-121-handoff.md) |
| #117 | [Contribution destinations, shared anchors and export identity](issue-117-handoff.md) |
| #116 | [Source-aware math, diagnostics and accessibility](issue-116-handoff.md) |
| #118 | [Bounded HTML/PDF export and recoverable publication](issue-118-handoff.md) |
| #79 | [Mermaid/D2/Graphviz neutral presentation and print coherence](issue-79-handoff.md) |
| #113 / E23 | [Semantic themes, safe custom themes, Quick Look and Finder](issue-113-handoff.md) |
| #120 | [Logical Save As progress, close prompts and Open latency](issue-120-handoff.md) |
| #119 | [External-file behavior, bounded probes and Release evidence](issue-119-handoff.md) |
| #88 | [Real native UI tests and exact-artifact verification](issue-88-handoff.md) |
| #53 | [Compatible old settings and deliberate legacy import](issue-53-handoff.md) |
| #18 / E17 | [Bootstrap migration, CLI, updater and distribution](issue-18-handoff.md) |
| #17 / E16 | [Final localization, native QA and string freeze](issue-17-handoff.md) |
| #115 | [Finite debt closure and exact-artifact proof](issue-115-handoff.md) |
| #148 | [Licensing, provenance, source-only archive publication and exact-artifact compliance](issue-148-handoff.md) |

## Implement shared contracts once

LocalResourceAccess (#121) owns contained resource snapshots and explicit none/single-file/directory grants. Export uses the same reader, while Quick Look receives only its actual grant. FileCore's authoritative monitored-document snapshots remain a distinct contract; its bounded executor does not import Preview or DocumentPresentation.

#117 owns destination admission, HeadingAnchorIndex and immutable ExportOrigin/ExportSnapshot. It starts with existing Theme values; E23 later resolves semantic palettes. #118 extends the same export operation with registered resource slots, progress, managed ownership and publication. DocumentPresentation depends on existing ExportService, never the reverse; it orchestrates rather than duplicates rendering.

#116 owns original-source MathSyntax admission and narrow pinned Textual/SwiftUIMath adaptations. Do not run the old post-Markdown dollar tokenizer after transporting admitted spans. Rendering identity, original source identity and transient markers are distinct.

E23 owns semantic palettes/theme catalog; #79 is its renderer unit. #120's save-operation tokens do not become forever document IDs. #18's CLI wait receipts follow stable logical document lifetimes across Save As. #53 owns compatible settings decoding shared by ordinary startup and import; #18 owns bootstrap admission before writers exist.

Read the retained-contract clarifications in READINESS_REVIEW.md before implementing #79/#119/#120. Consumer cancellation, actual worker completion and retained payload release are separate events. #121 defines reservation transfer into retained snapshots; #113 applies it to Quick Look reply holders without assuming callback completion frees their bytes. No consumer may infer resource authority from a pathname or release readiness from a test count.

## Execution order and remaining probes

[readiness.json](readiness.json) is the explicit acyclic unit dependency plan. Its 54 nodes (rebaselined 9 October 2026) include external inputs, E22, probes, implementation and final gates; they are not new issues or a requirement for 48 PRs. Whole-issue closure is not used where only a tested prerequisite is required. Do not bypass a failed prerequisite or hold all independent work while one external gate is unavailable.

After E22/rebaseline, begin the independent foundations: UI harness, settings compatibility, source-aware math/anchor values, export snapshot, save-progress work and E23 palette. Run the named narrow probes before their dependent integrations: **RESOURCE-OPEN, MATH-ADAPTER, ANCHOR-PARSER, PDF-PRINT, DIAGRAM-CONTEXT and QL-REPLY**. All six are NOT_RUN in this architecture task. Their owning documents specify positive controls, failure cases and the decision output. A failed probe needs a focused architecture correction, not invented API calls or weakened tests.

Integrate Export against tested reader/snapshot/anchor units; integrate shared presentation/Quick Look against actual math/diagram/palette/assembly capabilities. Finish settings/theme-dependent legacy import, bootstrap/CLI/updater and all in-app strings before final localization. Real UI/security/performance/accessibility results remain mandatory at the proper acceptance layer.

The public name MostlyText and owned mostlytext.app/mostlytext.dev domains are settled. Final technical identifiers, approved artwork, signing/translation access and required native-language review remain separate evidenced inputs. Consume latest actual design decisions and waivers without modifying the active design lane or reviving superseded studies. Do not publish or purchase services from this architecture instruction.

## Canonical release sequence

Rebaselined 9 October 2026 to the owner-approved **two-candidate** order (RELEASE_SEQUENCE.md, readiness.json and the checker agree):

**S:** software/UI stabilised, including release-app code, strings and compatible settings decoding. #115 stays open.
**V1:** private candidate 1 and the software/native #115 verification on that binary.
**Final E16**, then the **final signed candidate** built with the corresponding source already published (source-only, separately authorised; #148), then #148's exact-artifact compliance and the artifact/locale-sensitive #115 reruns on that binary.
**#115 closes**, then the **full-history repository cutover (#158)**, then **P:** separately authorised public promotion of the same verified bytes.

The change becomes active repository authority when this documentation PR is adopted. It changes ordering terminology, not acceptance criteria. Do not close #115 early, publish a binary to satisfy the source-offer check, or rebuild/re-sign an artifact after its proof and reuse the old approval.

## What was actually verified

READINESS_REVIEW.md records four complete-coverage review passes plus two focused continuation passes, 28 correction groups, retained decisions and per-issue entry conditions. These are self-reviews, not independent-provider approval or native execution.

Run the planning-only checker from the repository:

```sh
python3 planning/downstream/validate_readiness.py planning/downstream/readiness.json --self-test
```

The current local run passes **49 positive/negative checks**, in normal and optimized Python. It checks issue/file coverage, unique units, known dependencies/acyclicity, probe ownership AND prerequisite reachability, all implementation/probe work upstream of software-S, protected E22 work, required language/signing/authorization inputs and honest evidence labels. Tests mutate by unit identity and verify the intended defect is detected; valid row ordering is immaterial. The unchanged manifest remains 13 hand-offs, 48 nodes and six unrun probes.

The earlier 13-check run is superseded: it missed three reproduced prerequisite omissions, which have now been corrected. File-presence validation in the local container used actual GitHub-returned filenames, not a full clone; the checker identifies this as supplied_list. No Swift test, GUI, filesystem-race proof, signing, migration or release occurred. A structural PASS does not authorize implementation or publication or authenticate later runtime results.

At implementation, follow AGENTS.md, EPIC_STANDARD.md, RELEASE_HARDENING.md and each unit's allowed files/tests. Keep worktrees/branches safe, use the serial validation discipline, preserve failed evidence and record actual as-built corrections. Complete one reviewable unit, verify its real result and continue to the next eligible unit without another broad architecture exercise unless a concrete assumption fails.
