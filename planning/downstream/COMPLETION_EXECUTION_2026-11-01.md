# MostlyText macOS 1.0 completion execution contract

## Owner outcome and scope

Complete the existing macOS 1.0 capability and safety contract, qualify the
exact direct-distribution artifact, and close owning issues only from evidence.
The owner approved implementation on 1 November 2026 after selecting:

- macOS 1.0 only; later 1.1–1.10 work and iPad remain outside this effort;
- direct distribution first, with Mac App Store delivery separate;
- existing performance budgets, rather than an assumed waiver for the fallback;
- application history on master while preserving the website main branch;
- actual native-speaker review of French, Polish and Japanese translations.

All applicable manual/native journeys are performed through computer use on
CORTANA. They are not assigned to the owner for physical testing. Linguistic
review is a separate external dependency. Public source-archive publication,
public binary promotion and repository archival retain the action-specific
boundaries in RELEASE_SEQUENCE.md; prepare concrete reviewable outputs first.

## Baseline and evidence

Application master: 15c0fae22f7618e94c82681227057c66011be2a9.
Integration baseline: 7b8b4055796d7452fc6dd1b27ced71470c92623c.
Master CI and Compliance passed; integration is 21 commits ahead, none behind.
No current combined native/release qualification is inferred from those checks.

Use OPEN_ISSUE_ACCEPTANCE_REGISTER.md, RELEASE_EVIDENCE.md and the existing
readiness graph as the durable records; do not create another status database.
For each criterion retain owner, prerequisites, source revision, driver and
artifact identities, fixture, command/actions, actual result and residual gate.
Historical failures remain visible. A build, nonblank screenshot, input event,
known issue or green retry is not a native acceptance result.

Preserve dirty worktrees, independent clones, private candidates and evidence.
The prior #88 source is archived locally under
MostlyText-Assets/Completion-20261101/preservation/issue88 on the Fast SSD,
including tracked patches, imported sources and SHA-256 manifest. No private
user data belongs in a public evidence record.

## Dependency-ordered work

1. #88: enforce launch identity and paths before constructing persistent stores;
   finish the isolated build configuration and runner preflight; prove positive
   and negative controls without launching the app. Verify the separate safe
   GUI account/environment before native execution.
2. Accept existing drafts in dependency order: #519 resource and viewport
   authority; #532 export inputs; #520 after its failed presentation and
   performance gates; #541 reconciled with those viewport changes. #533 is
   diagnostic-only until the session race is explained and corrected or its
   need is superseded by concrete evidence. #119 may be temporarily parked,
   never treated as waived at final qualification.
3. #112/#183: reconcile all directly owned and delegated audit findings; finish
   persistence/recovery/session publication, conditional Save As, rooted
   mutation, search/navigation retirement, recents and selection fidelity.
   Exercise multi-cursor, IME, undo, search, snippets, transforms, encoding,
   EOL, TeX and command routing. Preserve the recorded noowners-drive exception
   and prove its warning and native filesystem behavior.
4. #459/#203: deterministically reproduce mounted highlighting failures and
   grammar reuse defects. Repair demonstrated causes; retain the fallback
   while meeting 50 ms incremental, 500 ms full-highlight and 8 ms synchronous
   main-thread targets. Do not remove known-issue markers without a repair and
   discriminating regression. Pin/reconcile dependency changes with #148.
5. #116/#117/#118/#119/#121/#155: finish math/accessibility/source navigation,
   shared anchors and export origin, bounded contained resources and output
   publication, real PDF/progress/cancellation, external-file matrix and
   extended mixed-renderer lifecycle proof. Keep actual network denial and
   resource accounting distinct from configuration strings and task cancellation.
6. #113: shared semantic palette, eight bundled themes (four light/four dark),
   declarative custom themes and safe persistence, Appearance UI, shared static
   presentation, installed Quick Look feasibility probe, Markdown-only provider,
   approved artwork and Finder/association evidence. Respect the existing
   downstream contracts and their concrete platform probes before broad work.
7. #53/#18: protected compatibility/import writer and complete legacy key map;
   idempotent bootstrap migration; embedded mostlytext CLI and document-lifetime
   wait semantics; pinned Sparkle integration and actual signed update rehearsal.
   Include all app strings before final E16.
8. #148: complete all LC obligations, notices/SBOM/licence UI, corresponding
   source and enforceable artifact checks. Ordinary compliance is not release
   compliance. The initial strict check reports seven unresolved findings.
9. Software stabilisation -> private candidate 1/native verification -> final
   #17 localisation and linguistic review -> authorised source-only archive
   publication -> final candidate 2, exact #148 checks and artifact-sensitive
   reruns -> #115 closure -> #158/mostlytext #1 cutover -> separately authorised
   public promotion of exactly the qualified bytes.

## #88 first-slice architecture and limits

Use a dedicated debug-derived UITestIsolated configuration with a per-attempt
UUID app bundle identity. Validate the test marker, identity and exact supported
launch-argument grammar before any normal store is selected. The requested
session must be empty and inside a fresh owner-only OS private temporary run
root. Fixtures must be regular owned files beneath its fixtures directory;
reject symlinks, hard links, permissive paths and implicit folder access.

Do not use Release with ignored test hooks. Ordinary Release rejects a UI-test
request before store construction. Test configuration does not restore AppKit
window-frame state. Fixtures use throwing setup and verified document identity;
cleanup preserves files if launch or process termination is uncertain.

These checks prevent configuration/path mistakes; they are not a proof against
hostile same-UID path replacement. A dedicated non-admin GUI test login with
verified denial of access to owner stores remains the operational boundary.
CORTANA currently has only the owner's ordinary login. No account, password,
permission, TCC, remote-access or owner-data change is performed by this slice.
The runner's execution hold remains until actual runtime isolation is proved.

The standalone Swift controls compile only the Foundation/Darwin launch guard;
they never instantiate AppDelegate or launch an app/test host. Python runner
controls also perform no UI action. Build-for-testing verifies compilation and
product identity only. App-hosted and native suites retain NOT_RUN status until
the safe execution lane is available.

## Review, verification and closure

Each bounded source slice receives regression evidence and source review, then
locked tests, strict lint/format, compliance and Release builds as applicable.
No broad reformat or dependency update is incidental to the change. Validate
combined integration checkpoints before master merges. Record review fixes and
verification in resolved PR threads. Do not call self-review independent review.

Execute the complete critical UI inventory after E22/E23 and qualify the final
unchanged signed artifact through public UI in a disposable account/VM. Cover
file/recovery, editing/IME, preview/grants/hostile content, math/diagrams, exports,
themes/Finder/Quick Look, accessibility, languages, installation, CLI and updates.
No required case may disappear through a rename, skip or build-only result.

At cutover preserve both repositories' refs and website PR #3. Use ordinary
non-destructive ref pushes rather than --mirror into a populated destination.
Verify ancestry, default branch, CI and current links before archival.

Release-ready requires zero unresolved release-relevant P0/P1/P2, all required
behavior/evidence and language review, existing performance targets, qualified
signed bytes and verified direct-delivery/update preparation. A release tracker
retains an unperformed publication action rather than manufacturing closure.
