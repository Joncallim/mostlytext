# macOS 1.0 execution and authorization sequence

Status: adopted through [PR147](https://github.com/Joncallim/macdown_2/pull/147), merged 10 October 2026 at 7fa4cbcacd11ed639356ed45dd24251190c968e8; originally proposed 26 September and rebaselined 9 October to the two-candidate sequence and source-archive resolution. No release is authorized by its existence. It clarifies RELEASE_HARDENING.md sections 7–8 without weakening issue acceptance, artifact identity, security, fidelity or language requirements.

## Why the old shorthand must be expanded

The historical shorthand `E22 -> identity -> E23 -> #115 -> final E16 -> E17` mixed implementation milestones with final issue closure. #115's full matrix requires final E16 plus exact signed-candidate UI/VoiceOver/export/Quick Look evidence, while E17 prohibits public production approval before #115 closes. Treating all arrows as whole-issue closure creates a cycle. An earlier revision of this document resolved it with a single private candidate and put final E16 before #115 closure; the owner's amendments (September 30 and the 9 October rebaseline) instead use **two candidates**, and this document now says so. Prose, `readiness.json` and `validate_readiness.py` encode the same state machine and are changed together.

## The sequence (two candidates)

1. **S — software and UI stabilised.** Complete E22 under its own plan, final technical identity intake and E23 capability work, E17's application-side bootstrap/settings/legacy migration/CLI/updater, and every required carried-forward product correction, each with its own catalogs and tests. Compatible settings decoding (#53) precedes every writer of migrated or imported settings. S requires an exact source/identity/UI baseline and no known required unimplemented behaviour hidden as a manual task. #115 stays OPEN.
2. **V1 — private candidate 1 and software/native verification (#115).** Build a private, unapproved signed/notarised candidate from S. Run the finite software and native #115 matrix on that binary: UI harness suites, VoiceOver/native modal behaviour, file/recovery, HTML/PDF, math/diagram, theme, Finder/Quick Look, clean installation, stateful migration and a signed update rehearsal. Failures return to S, produce a new candidate and rerun the affected proof.
3. **Final E16.** Only after V1: the final actual resource/string audit, plural/layout work, native-language review and the freeze of the exact source/translation/UI baseline.
4. **Final signed candidate (candidate 2).** Built from the frozen baseline. Its notices and source offer point at durable, already-published corresponding-source locations (see below), so those exist BEFORE this candidate is generated and notarised. Then run #148's exact-artifact compliance verification and every artifact- or locale-sensitive #115 observation again on this binary (`final-artifact-reruns`); the compliance gate is not relaxed to make a checker pass.
5. **#115 closes** once V1, final E16, the artifact-sensitive reruns and #148 are all evidenced.
6. **Final release-history/cutover verification (MostlyText #16).** The owner explicitly authorized the earlier physical repository and backlog cutover on 3 November 2026: complete application history is already in `Joncallim/mostlytext` on `main`, all 17 engineering issues were transferred, and the website source is separate. That supersedes the original timing requirement to keep the backlog in macdown_2 until this step. Before promotion, verify that the final qualified release baseline/history is present in MostlyText and that historical receipts still name their original source; the earlier move is not debt-gate closure or release permission.
7. **P — separately authorised public promotion.** Forbidden while #115 is open or the cutover has not happened. A documentation task, a green workflow, an architecture review or a private signature is not that authorisation.

## Source-archive deadlock and its resolution (#148)

The previous archive plan attached Graphviz/D2 source packages to the **draft** GitHub Release and verified anonymous retrieval before public promotion. A draft release and its assets are unpublished and access-controlled, so "anonymous, no-login retrieval" cannot succeed while they sit in a draft; `source_offer` could therefore never become `verified`, the E17 script's pre-notarisation check could never pass, and the final candidate/#148 could never finish. Following that plan and the order above together is a deadlock.

Resolution: the corresponding-source objects are a **separately authorised, source-only publication**, independent of any binary or appcast promotion. They are immutable, versioned, hash-listed packages (upstream source archives, our patch, licence texts, `SHA256SUMS`, matching notices/SBOM text) published to a durable public location (the website's opensource folder and/or a source-only release or archive that contains no application binary). Their URLs and digests are frozen first and then written into the final notices before candidate 2 is built. Publishing them is a public act and requires the owner's explicit approval (`source-archive-authorization`); no application binary is made public to satisfy the checker, and the compliance gate is unchanged. See `compliance/ARCHIVE_PLAN.md` and `issue-148-handoff.md`. Tests: anonymous retrieval of a draft asset FAILS (documented counterexample); a no-cookie fetch of the published objects matches `SHA256SUMS`; notices embed those exact locations; no binary is reachable from the source location.

## Promotion mechanics

Promote the SAME bytes that passed the final reruns. Do not rebuild, re-sign, rewrite Info.plist, alter entitlements, replace resources or swap the artifact after approval. Upload immutable versioned assets/notes first, verify downloaded bytes/signatures, and publish the stable appcast last. Retain the previous known-good release. Any changed identity/content invalidates affected proof and requires reverification before promotion.

## Preserved release requirements

Zero release-relevant P0/P1/P2; only explicitly accepted cosmetic P3. No required unverified/blocked/accepted-debt row. Genuine native tests are not substituted by build-for-testing. No source normalization or loss of authoritative preferences/session/recovery/themes/snippets. Offline rendering and exact resource grants remain mandatory. The legacy/development migration and two signed-build update rehearsal are still required. The final human/language/artwork checks remain as actually approved by their owning records; a real waiver must be named as a waiver, not invented by an implementation agent.

## Adoption and ongoing use

RELEASE_HARDENING.md links this sequence as its current execution interpretation. The revised #17/#18/#115 hand-offs refer here. At adoption, add short cross-links to relevant issue discussions rather than replacing their product acceptance text. Older statements that final localization waits for all of #115 to close are superseded only as sequencing, not as a waiver of any criterion.

Use planning/downstream/readiness.json for unit dependencies and named unrun probes. It is a planning artifact, not the future runtime release-evidence manifest and not an executable release approval.

## Current engineering route and historical planning model

[ENGINEERING_REMAINDER.md](ENGINEERING_REMAINDER.md) names current implementation
and acceptance ownership. The source-only notice/review packages are concrete
local preparation; independent source/runtime review, explicit publication and
anonymous retrieval still precede final signed-artifact promotion. The current
license window is implemented; its native acceptance remains open.

`downstream/readiness.json` and its validator are retained as the historical
architecture/dependency model, not execution receipts. Their old repository and
issue numbers describe the reviewed baseline and resolve through
[ISSUE_TRANSFER_MAP.md](ISSUE_TRANSFER_MAP.md). The guarded repository-cutover
node still enforces a final handoff after the debt gate; it does not undo the
owner-authorized earlier physical transfer or claim that an unrun probe passed.
No machine release guard, dependency, execution result or approval field is
changed by this documentation reconciliation.
