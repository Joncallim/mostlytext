# Epic implementation and readability standard

This document defines the required planning and communication standard for every new or materially revised MostlyText epic.

The purpose is simple: an epic should be precise enough that an implementation agent can execute it without inventing architecture, while remaining understandable to a human owner who did not participate in the implementation conversation.

## 1. Three layers of authority

Every epic has three layers. They solve different problems and must not be collapsed into one document.

### Layer 1 — Epic issue: product contract

The GitHub issue states what the user should get and why it belongs in the product.

It must contain:

- owner summary in plain English;
- user problem and intended outcome;
- representative user journeys;
- dependencies;
- scope and explicit non-goals;
- user-visible acceptance criteria;
- release or milestone placement.

The issue should avoid implementation detail unless the detail is itself a product constraint.

### Layer 2 — Implementation architecture: engineering contract

Before coding starts, inspect the current `main` branch and write `planning/epic-NN-implementation.md` from the live repository state.

This document is the binding engineering contract for the epic branch. It resolves stale assumptions in the issue and makes important technical decisions before implementation begins.

### Layer 3 — Implementation slices: execution contracts

The implementation architecture is divided into dependency-ordered slices. Each slice must be small enough that a worker can implement it without choosing a new architecture.

A slice may require normal coding judgement, but it must not require the worker to decide ownership boundaries, data flow, persistence semantics, concurrency policy, public interfaces, or product behaviour.

If a slice encounters a false architectural assumption, it stops and escalates rather than silently designing a replacement system.

---

## 2. Definition of Ready

An epic is not ready for implementation until all of the following are true:

- [ ] Upstream dependencies required by the epic are merged or their exact stable interfaces are known.
- [ ] The current `main` SHA is recorded as the implementation baseline.
- [ ] The relevant live code, tests, planning documents and open follow-up issues have been inspected.
- [ ] Stale assumptions in the original issue are listed and explicitly reconciled.
- [ ] The owner summary and user journeys are understandable without reading code.
- [ ] Product decisions that materially change implementation are resolved or explicitly deferred.
- [ ] Module ownership and dependency direction are decided.
- [ ] Important interfaces and state transitions are specified.
- [ ] Failure behaviour is specified, not only the success path.
- [ ] The required test fixtures, adversarial corpus and performance inputs are identified.
- [ ] Verification commands and manual dogfood steps are known.
- [ ] Implementation slices have explicit completion and stop conditions.

If any of these are genuinely unknowable until a small technical spike is performed, the spike is a named pre-implementation slice with a narrow question and a written decision output. It is not an excuse to begin broad implementation.

---

## 3. Required implementation-architecture sections

Every new `planning/epic-NN-implementation.md` must contain the following sections unless one is explicitly marked "not applicable" with a reason.

### 3.1 Owner summary

Open with a short section written for a human owner. It should answer:

1. What changes for the user?
2. Why are we doing this now?
3. What is the main technical approach, in ordinary language?
4. What are the main risks or compromises?
5. What is deliberately not being built?

Do not make the owner reconstruct the purpose from type names, issue IDs or internal jargon.

### 3.2 Baseline and repository reconciliation

Record:

- baseline `main` SHA;
- relevant shipped modules and behaviours;
- assumptions from older plans that no longer match the repository;
- open bugs or follow-up issues that intersect the epic;
- dependencies that are production-ready versus scaffolding.

Live repository behaviour wins over stale planning text. When the plan changes, document why.

### 3.3 User journeys

Specify end-to-end behaviours, including recovery from errors.

A feature noun such as "Mermaid support" is insufficient. A journey such as "type a Mermaid fence, see the preview update, receive a useful syntax error, fix it, then export the diagram to PDF without rasterisation" is testable.

### 3.4 Non-negotiable invariants

List the rules that implementation must not violate. Examples include:

- document edits publish through one existing path;
- dirty local text is never silently overwritten;
- expensive rendering does not block the main actor;
- unsupported formats fail closed rather than receiving Markdown behaviour;
- no hidden fallback changes the security model.

### 3.5 Ownership and dependency boundaries

State which Swift package target or app layer owns each new concept and which dependency directions are permitted.

Do not create a new abstraction solely because a possible future feature might use it. New seams must solve a current requirement or remove a demonstrated coupling problem.

### 3.6 Types and interfaces

Specify the important protocols, models, enums and function contracts before workers implement them.

Exact spelling may change when required by the SDK, but the semantic contract must be fixed: inputs, outputs, ownership, error behaviour and threading expectations.

### 3.7 State and data flow

Show how information moves through the feature. Use short text diagrams where useful.

For stateful features, document meaningful transitions and who is allowed to cause them.

### 3.8 Concurrency and cancellation

For asynchronous work, state:

- actor or executor ownership;
- what may run on `MainActor`;
- cancellation behaviour;
- stale-result suppression;
- lifecycle teardown;
- `Sendable` expectations;
- what happens when a document changes while work is in flight.

### 3.9 Failure model

List expected failures and the required user/system response. Consider, where applicable:

- malformed input;
- unavailable dependency;
- timeout;
- cancellation;
- renderer/compiler crash;
- corrupted cache or persisted state;
- file movement/deletion during work;
- repeated rapid edits;
- oversized or pathological input;
- export failure;
- unsupported capability.

A feature is not robust if only its happy path is specified.

### 3.10 Security and trust boundary

State what code or content is trusted, what is untrusted, and which capabilities it receives.

This is mandatory for JavaScriptCore execution, text-filter commands, HTML, external processes, user-provided diagram source, file access and future extension work.

### 3.11 Resource and performance budgets

Define measurable ceilings where the feature can affect responsiveness or memory.

Specify whether evidence is:

- unit/package benchmark;
- integration measurement;
- complete app-path Release measurement;
- manual observation.

Do not present a package benchmark as proof of whole-app latency.

### 3.12 Accessibility and localisation impact

Feature epics own their basic accessibility and localisation behaviour. E15/E16 perform final audits; they are not dumping grounds for accessibility or hard-coded strings introduced earlier.

### 3.13 Export and interoperability

For document features, state what happens when the document is:

- reopened;
- copied or pasted;
- stored in source control;
- exported to HTML/PDF;
- opened when an optional renderer is unavailable.

Text-authored features should preserve their readable source as the durable document representation unless an epic explicitly decides otherwise.

### 3.14 Test and evidence matrix

Map important requirements to evidence. Include the relevant subset of:

- pure unit tests;
- integration tests;
- app/UI tests;
- regression tests;
- performance measurements;
- adversarial fixtures;
- Release-build dogfood steps.

Every user-visible acceptance criterion needs at least one named verification path.

### 3.15 Adversarial corpus

Identify malformed, unusually large and otherwise difficult fixtures before implementation is considered complete.

Pretty sample documents are demonstrations, not robustness evidence.

### 3.16 Expected files and symbols

List likely files/symbols to change and important areas that must not be modified.

If the implementation unexpectedly requires a forbidden or architecturally unrelated area, stop and reassess the contract.

### 3.17 Implementation slices

Each slice must state:

- goal;
- dependencies;
- allowed ownership area/files;
- important types or behaviours to implement;
- tests/evidence required;
- verification commands;
- explicit stop/escalation conditions.

Slice IDs may be used for tracking, but a slice title must describe the actual work in plain English.

### 3.18 Definition of Done and residual risk

End with the exact completion gates and a short list of consciously deferred limitations.

Deferred limitations that can reasonably cause future work should become GitHub issues rather than disappearing into a PR conversation.

---

## 4. Definition of Done

An epic is complete only when all applicable items below are satisfied:

- [ ] Product acceptance criteria are demonstrated.
- [ ] Package/unit/integration/UI tests required by the architecture pass.
- [ ] Formatter and strict lint pass.
- [ ] The app builds in Release configuration.
- [ ] User-facing performance claims have evidence at the appropriate layer.
- [ ] Required manual dogfood journeys have been executed on the real app.
- [ ] Error and destructive paths have been exercised, not just normal use.
- [ ] Accessibility and localisation requirements introduced by the epic are covered.
- [ ] Export/interoperability behaviour is verified where relevant.
- [ ] README, roadmap, issue and architecture documents describe what actually shipped.
- [ ] Remaining risks and intentionally deferred work are recorded.
- [ ] The PR description explains the finished result in language the owner can understand without reading the diff.

"Merged" and "CI green" are necessary but not sufficient definitions of done.

---

## 5. Human-readable engineering standard

Repository history and documentation are for humans first. Agent efficiency must not make the project opaque.

### 5.1 Write owner-first

Architecture documents, PRs and major issue updates must put plain-English meaning before implementation detail.

Prefer:

> External edits now reload clean documents automatically, while local unsaved edits enter an explicit conflict state so neither version is lost.

Avoid:

> Wire E18 watcher reconciliation through the workspace publication seam.

The second sentence may be useful later in a technical section; it must not be the only explanation.

### 5.2 Define jargon and abbreviations

- Define non-obvious abbreviations on first use.
- Use concrete nouns instead of internal shorthand when possible.
- Issue and slice identifiers supplement descriptions; they do not replace them.
- Tool/model names and orchestration terminology do not belong in product or architecture prose unless they materially affect the repository.

### 5.3 Commit messages

Commit subjects must describe the outcome in plain English.

Preferred form:

`<area>: <what changed and why it matters>`

Examples:

- `editor: preserve native undo when Markdown assists rewrite a line`
- `preview: cache Mermaid renders so typing does not repeat identical work`
- `docs: define the epic implementation and readability standard`

Avoid subjects such as:

- `E20 S3`
- `wire seam`
- `fix stuff`
- `agent changes`
- `follow-up`
- `WIP`

When the reason is not obvious from the subject, the commit body should contain short `What`, `Why`, and `Verification` paragraphs. A commit must be understandable without the chat or agent session that created it.

### 5.4 Pull requests

Every PR begins with these human-facing sections before detailed implementation notes:

1. **What this changes** — user/system outcome.
2. **Why** — problem being solved.
3. **How it works** — plain-English design, not a symbol dump.
4. **What I should test** — concrete owner/dogfood steps.
5. **Risks and limits** — what remains imperfect or deferred.
6. **Verification** — automated and manual evidence.

Detailed type-level notes may follow those sections.

### 5.5 Documentation and code comments

- Explain purpose and rationale, not a transcript of implementation activity.
- Do not leave comments that refer only to an agent conversation, prompt, or temporary plan.
- Prefer domain language a future maintainer can learn from the repository itself.
- If a document uses more than a few specialised terms, add a short glossary or define them in place.
- Do not hide important behaviour behind unexplained metaphors such as "seam", "gate", "tail", "plumbing" or "wiring" when a precise description is available.

### 5.6 Human comprehension check

Before an architecture document or PR is considered ready, ask:

> Could the owner understand what changed, why it was chosen, what could go wrong, and how to test it without reading the implementation diff or the originating chat?

If not, the document is not finished.

---

## 6. Stop and escalation rule

Workers must stop and return the mismatch to the architect/reviewer when any of the following occurs:

- a required existing API or invariant does not exist on the recorded baseline;
- implementing the slice requires a new cross-module dependency not authorised by the architecture;
- a forbidden file or subsystem must change;
- user-visible behaviour is ambiguous;
- a security, persistence or document-safety assumption proves false;
- the measured performance path is materially worse than the budget and a structural redesign is indicated;
- passing the tests would require weakening an existing test or acceptance threshold.

The worker may propose options, but must not silently expand the architecture.

This rule is intentionally conservative: one explicit escalation is cheaper than allowing an implementation shortcut to become a permanent architectural dependency.
