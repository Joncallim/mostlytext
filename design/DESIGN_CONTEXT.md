# MostlyText design context

**Owner summary.** This is the short, canonical starting point for product,
visual, brand and UX design work on MostlyText. It records durable facts and
where the sources of truth live, so a future design session can pick up context
without replaying project history. It is not a design spec and not a diary.
Decisions live in [`DECISIONS.md`](DECISIONS.md).

## Product

- **MostlyText** is a native macOS (26+) text and Markdown editor descended
  from MacDown. The development codename in the code is still `MacDown 2`.
  The name was settled 2026-09-25 (`planning/MIGRATION_PLAN.md`, open item O1).
  The mark and artwork are frozen for 1.0 (D-031). The bundle ID and CLI
  name are set by the release-hardening identity cutover
  (`planning/RELEASE_HARDENING.md` §5.1), not by the design lane.
- It should work well for everyday text, not only as a Markdown or developer
  tool.
- Only features that are already built count. Design and marketing must not
  invent features.
- Domains owned: `mostlytext.app` (product site), `mostlytext.dev`.

## Design principles

1. Native macOS behaviour first (Liquid Glass on macOS 26, AppKit/SwiftUI
   controls, system materials). Only depart from it for a stated reason.
2. Content comes first and the window chrome stays quiet.
3. Typography should be excellent and information clear, without clutter.
4. Light and dark mode are both fully designed. Reduce Transparency, Increase
   Contrast and Reduce Motion are respected.
5. Accessibility shapes the design from the start. It is not a final check.
6. Windows behave well at every size, from narrow to wide.
7. Avoid web-app conventions where macOS already has a better pattern. Tabs are
   **native `NSWindow` tabs**, so there is no in-app tab bar.
8. Aim to converge: offer a few genuinely distinct options, then choose.

## Brand

- Name: MostlyText. Wordmark casing is `MostlyText`, with a capital T. The wordmark
  leans to match the mark (D-012). Don't use SF Pro in brand artwork: its
  licence doesn't allow logo use.
- Primary identity direction: the symbol meaningfully combines **M** and **T**.
  Chosen mark: **Slant**, an M and T sharing one stem, leaning forward, with a
  wedge cut on the crossbar. Geometry is release-candidate frozen, not frozen
  (D-018). The 16 px files are microglyphs for ≤17 px only; never enlarge them (D-020).
  **Production lean is 10°, superseding the original 12° construction
  (D-027, 2026-09-25/26).** The cascade is complete (D-029): `slant-16.svg`,
  `slant-32.svg`, `slant-master.svg`, `slant-icon-16-inner.svg`, the production
  wordmark/lockup pipeline (`design/brand/slant/production/`) and the canonical
  Figma file are all regenerated at 10°, with the wordmark's three optical
  corrections re-measured (not reused) from the 12°/2.6° numbers. **Gate 2
  (macOS icon set) is closed (D-028):** a `.icon` file built as a project
  resource adjacent to `Assets.xcassets` (not inside it — see
  `design/evidence/2026-09-26/icon-art/README.md` for the exact steps)
  compiles correctly and renders the mark in the real Dock and Finder at true
  small size. The Figma file's own title still reads "(Slant 12°)" — that
  field can't be renamed via the Plugin API (D-029) and needs a person to
  update it through the Figma UI.
- **Handoff and gates:** `design/FIGMA_HANDOFF.md` (everything the Figma session
  needs), `design/brand/PROVENANCE.md` (licences, canonical files),
  `design/validation/read-test/` (blind human test: round 1 exploratory; formal gate waived by the owner, D-026) and
  `design/brand/TRADEMARK_SEARCH.md` (register search record: word-mark and figurative searches complete on WIPO/USPTO/IPOS, 2026-09-26/27; no exact word-mark match found; one live Singapore "MT" mark flagged (D-030). **Gate 4 is owner-waived/deferred for the 1.0 open-source release (D-031), not passed**: formal registration and legal review are deferred on proportionality and privacy grounds, no legal clearance is claimed, and registration is revisited if the brand gains material value — see the file's owner summary and search log).
- **Freeze status for 1.0 (D-031):** Gates 1 and 2 closed, Gate 3 waived (D-026), Gate 4 deferred (D-031). The public identity is frozen for 1.0; the branding cutover in `planning/RELEASE_HARDENING.md` §5.1 can proceed.
- The mark must work at macOS app-icon size, at favicon size (16 px), in
  monochrome, on light and dark backgrounds, and in a wordmark lockup.
- Production app icon: `MacDown2/MacDown2/AppIcon.icon`, integrated from the
  byte-identical D-028 source `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon`.
  It replaces the document placeholder appiconset. Compile-time appearance/tint
  inspection does not establish fresh Dock/Finder/native acceptance for this build.

## Sources of truth

| What | Where | Status |
|---|---|---|
| Repository | `github.com/Joncallim/mostlytext`, branch `main` | live |
| App sources | `MacDown2/MacDown2/`; packages in `MacDown2/Packages/MacDownKit/` | live, changing |
| Build / run | macOS 26 + Xcode 26: see the commands table in `AGENTS.md`. Judge feel on a **Release** build | needs a Mac; cloud design sessions run on Linux and **cannot run the app** |
| Screenshots | `design/evidence/YYYY-MM-DD/` (capture protocol below) | **none yet** |
| Figma | [MostlyText — Brand Identity (Slant 12°)](https://www.figma.com/design/x5wTgOFnR9GgNFfUqWwKmX): 8 pages, components for the mark (master, 32 optical, 16 microglyphs), wordmark, lockup and app icon sources, plus brand colour, theme and spacing variables | **live**; the production source for brand assets and the visual source of truth (D-024). Product UI is not in it yet |
| Brand assets | `design/brand/gen2/`: source geometry in `marks.mjs`, exported SVGs, comparison board (`node build.mjs` rebuilds `board.html`; published at https://claude.ai/artifact/HnqRCjVR1UPxFtWC9KnAwW). Gen-1 board: owner's image "Logo concepts — five directions for the T" (not in repo) | **Slant chosen (D-010).** Refinement in `design/brand/slant/` (board: https://claude.ai/artifact/CxLEqf5TCcFrEMMo1uN4Ni); `slant/marks.mjs` holds the parameterised geometry. Lockup board: https://claude.ai/artifact/BEM1dsLaq9Wf6jfE4KeRBV (`node lockup.mjs`). **Pre-freeze validation and production masters:** `design/brand/slant/validation/` (board: https://claude.ai/artifact/KdvvQKM2q4pV93baFvntnV, `node build.mjs`). **Production outlines** (mark flattened, wordmark outlined and corrected, lockup): `design/brand/slant/production/` (D-024, D-025). Earlier rounds in `gen2/` and `gen3/` are kept as a record |
| Design tokens / themes | Editor/preview themes: `MacDownKit` `Themes` module; the chrome follows system colours | not yet a named token set |
| Polish/identity contract | `planning/epics/EPIC-15-liquid-glass-polish.md`; `planning/RELEASE_HARDENING.md` §5.1 | binding for release |
| Surfaces with UI tests (a list of what exists) | `MacDown2/MacDown2UITests/*.swift` file names | live |

## Working boundary

The design lane is read-only toward implementation code. Design findings go to
the implementation lane as bounded issues with: evidence, expected behaviour,
the design requirement, and a narrow fix. Design files live under `design/`
only.

## Screenshot capture protocol

Design audits depend on screenshots of the running app. Cloud sessions cannot
run it, so captures are made on a Mac from a **Release** build and committed to
`design/evidence/YYYY-MM-DD/`. File names follow the pattern
`<surface>-<light|dark>-<narrow|wide>.png`. Narrow is about 700 pt wide; wide is
about 1440 pt. Capture only states that actually exist:

1. First run / welcome and empty window
2. Editor with a representative Markdown document (headings, lists, code, table, link)
3. Editor and preview side by side; preview only
4. Folder sidebar open, and the outline view
5. Find / replace bar active, with matches
6. Settings (every pane)
7. Several native tabs open, one with unsaved changes (dirty state)
8. Error states that can be reached: external file change prompt, a math or
   diagram render error
9. The toolbar at rest and with the window inactive
10. Accessibility variants for 2 and 3: Increase Contrast, Reduce Transparency

A shortcut for engineers: add `XCTAttachment(screenshot:)` with
`lifetime = .keepAlways` to the existing UI tests. Then
`xcrun xcresulttool export attachments` produces the same set.
