# MostlyText acceptance status — 3 November 2026

Initial acceptance baseline: main `f660e30f61c0b48551fb450ee9afd24ba35d50ae`.
The later scoped attribution integration and its exact resource checks are recorded below.
This dated status distinguishes source integration, local prerequisites and
acceptance. The live backlog is [MostlyText issues](https://github.com/Joncallim/mostlytext/issues);
[the number map](ISSUE_TRANSFER_MAP.md) explains imported historical references.

| Area | Observed result | Remaining owner issue |
|---|---|---|
| Source integration and automated checks | Full normal ARM CI41593264872: 3,325 package tests/462 suites, two existing known Neon issues; 600 app tests/122 suites; locked Debug/Release app/mostlytext builds, compilation, lint/format and pins pass. Final-main Compliance41597509034 passes | #17 audit and #8 closure gate still require their broader acceptance |
| Brand source | Frozen Slant AppIcon integrated; MostlyText display/welcome/sample/error copy; app/type/storage naming documented | #16 identity; fresh native presentation remains #7 |
| Theme naming | app.mostlytext.theme and .mostlytext-theme are implemented in project.yml and ThemeExportDocument | Native management/panel/accessibility evidence remains #7 |
| Native execution here | UID501 console; UID502 test account has no GUI domain; protected staging absent; nonprompting sudo refuses | #5 UI triage; never execute the owner-data paths to bypass this prerequisite |
| Signing discovery here | Valid Developer ID Application identity for team 968BRM85G5 found | #4: actual signing/key authorization/hardened-runtime acceptance not executed |
| Notarization preflight | Real script stops because documented mostlytext-notary keychain profile is absent | #4: credential profile, submissions, stapling and online/offline Gatekeeper acceptance remain open |
| Source/nonrelease artifact inventory | Passes; current scoped attribution checks include 142 local Compliance controls | #14 final compliance is a separate strict gate |
| Strict release compliance | Six failures remain, detailed below | #14: acceptance is blocked before an RC can be submitted |
| Repository preview | Source SVG/JPEG ready and visually checked; settings upload did not persist and native chooser fallback is blocked by the locked desktop | #16: install/read back the social preview remains open |
| Website | Separate mostlytext-site source/license; current FAQ and source/backlog links merged | No deployment was initiated; historical roadmap is explicitly dated |

## Strict release failures observed here

The actual `check --release --artifact` run against the compiled brand candidate
reported these six failures. It did not create or submit a signed release:

1. D2 corresponding-source URL is planned, not verified by anonymous retrieval.
2. D2 source-graph/font Reserved Font Name review and upstream-plus-patch
   publication remain incomplete.
3. Mermaid's exact bundled dependency versions/licenses/texts remain incomplete.
4. Graphviz corresponding-source URL is planned, not anonymously verified.
5. Complete Graphviz/Viz/Expat corresponding-source assembly/review/publication
   remains incomplete.
6. Remaining embedded Graphviz/Emscripten attribution audit remains incomplete.

## Scoped Mermaid attribution progress — 3 November 2026

Cytoscape's own complete MIT text and the credited Bézier/jQuery-event helper
notices are now separately registered and generated with source-map evidence.
See [the checkpoint](../compliance/evidence/cytoscape-borrowed-attribution/README.md).
[PR23](https://github.com/Joncallim/mostlytext/pull/23) is integrated at c938a4ad;
109 local controls and hosted Compliance pass. The compile-only Release artifact
contains byte-identical new notices and its unchanged Foundation-only reader loads
all three credits. This is resource validation, not native license-screen acceptance.
It closes those bounded notice gaps. It does not remove the Mermaid strict
failure: remaining package/embedded-helper review, Rough.js, candidate provenance
and final artifact evidence remain. The strict release failure count stays six.

## Remaining engineering ownership

| Issue | Remaining contract |
|---|---|
| [#3](https://github.com/Joncallim/mostlytext/issues/3) | Localization, language overrides, plural/layout/VoiceOver/native-speaker review and final freeze |
| [#4](https://github.com/Joncallim/mostlytext/issues/4) | Installed migration, CLI/package transition, signing/notarization, updates and exact release artifacts |
| [#5](https://github.com/Joncallim/mostlytext/issues/5) | Protected native UI acceptance, beginning with genuine focus/control evidence |
| [#6](https://github.com/Joncallim/mostlytext/issues/6) | Editor behavior, full-size Release responsiveness and residual text workflows |
| [#7](https://github.com/Joncallim/mostlytext/issues/7) | Native themes/appearance, document icons/Finder, Quick Look and accessibility |
| [#8](https://github.com/Joncallim/mostlytext/issues/8) | Release-relevant carried-forward debt; source completion does not waive native gates |
| [#9](https://github.com/Joncallim/mostlytext/issues/9) | Math correctness, accessibility and preview/export parity |
| [#10](https://github.com/Joncallim/mostlytext/issues/10) | Contribution/TOC/palette residual semantics and native navigation |
| [#11](https://github.com/Joncallim/mostlytext/issues/11) | Export security, ownership/crash policy, native PDF/print and parity/performance evidence |
| [#12](https://github.com/Joncallim/mostlytext/issues/12) | External-file native behavior, lifecycle and end-to-end performance |
| [#13](https://github.com/Joncallim/mostlytext/issues/13) | HTML-preview containment, MIME/cancellation/generation and native consumer proof |
| [#14](https://github.com/Joncallim/mostlytext/issues/14) | Six strict compliance failures, source offers, native license surfaces and exact signed artifact |
| [#15](https://github.com/Joncallim/mostlytext/issues/15) | Unresolved extended-session WebKit hangs; no weakened timeout or root-cause claim |
| [#16](https://github.com/Joncallim/mostlytext/issues/16) | Complete public/packaged identity and migration handoff, with separate native gates |
| [#17](https://github.com/Joncallim/mostlytext/issues/17) | Audit-owned correctness/lifecycle/authority and delegated exact/native acceptance |
| [#18](https://github.com/Joncallim/mostlytext/issues/18) | Incremental parsing and genuine full-size Release keystroke budget |
| [#19](https://github.com/Joncallim/mostlytext/issues/19) | Tree-sitter Debug abort, edit geometry/lifecycle/stale-completion and Release proof |

These whole issues remain open; completed source sub-items are checked with
specific evidence. There is no release or native acceptance claim in this table.
[Identity handoff](IDENTITY.md), [current signing brief](MAC_SIGNING_BRIEF.md) and
[historical release evidence](RELEASE_EVIDENCE.md) provide the detailed contracts.

## Nested notices and engineering documentation — 3 November 2026

The current [package checkpoint](../compliance/evidence/mermaid-package-notices/README.md)
adds 73 complete selected package texts alongside the existing Cytoscape record,
covering all 74 mapped package records. The two candidate versions remain visibly
unresolved. [Build-reference notices](../compliance/evidence/nested-build-attribution/README.md)
add 22 conservative records for Rough.js/D2/Bison/Emscripten sources. No renderer,
Swift source, dependency lock or native guard changes. All 131 local Compliance
controls pass; exact source-map and build-input replays pass. The
[Graphviz local source-review package](../compliance/evidence/graphviz-source-review/README.md)
now has a deterministic assembler, manifested digest and corruption controls.
It is not approved as complete corresponding source or published.

[The current license-window contract](../compliance/LICENCES_UI.md) replaces stale
unstarted/Textual instructions with the actual native plain-text implementation
and explicitly retains the absent original Help-menu integration requirement.
[Remaining engineering ownership](ENGINEERING_REMAINDER.md) names unfinished
implementation, diagnosis, native acceptance and release/publication work for all
17 open issues. Completing these documentation and notice units does not close
the broader issues. All six strict release failures remain; origin ambiguities,
independent source/font/runtime review and exact signed-artifact gates are not
waived. No local app/UI execution or publication is claimed.

## Thenable notice linkage

[The Thenable checkpoint](../compliance/evidence/thenable-mit-declaration/README.md)
adds the standard MIT terms expressly named by its original declaration, with
the actual author credit and positive emitted-code probes. This is an explicitly
documented assembly, not a fabricated upstream LICENSE file. The scoped full-text
linkage gap is resolved; other Mermaid embedded/generated origins and all six
strict failures remain. Native, legal-clearance and signed-artifact claims are
not inferred from this notice correction.

## Generated parser runtime attribution

[The runtime checkpoint](../compliance/evidence/esbuild-parser-runtime/README.md)
adds the complete esbuild MIT notice with two full matching helper bodies and
positive emitted-code probes. Its qualified identity does not invent an exact
emitting compiler version. The scoped preamble classifies 452 of the original
3,980 unassociated parser positions; 3,528 remain outside this classification.
The original report, all six strict failures and native/exact-artifact gates remain.
