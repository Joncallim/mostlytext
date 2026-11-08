# Selected plain-String sink checkpoint — 9 November 2026

This is a bounded source correction for E16, stacked locally on the reviewed
export-panel catalog delta from PR164. It does not satisfy the issue's complete
hard-coded-string audit or final language freeze.

## Changed routes

- The native window title and ordinary/held export filename fallbacks now use
  the app's existing `Untitled` key. Workspace's own Save As filename stem uses
  a new `Untitled` key in its package bundle; file extensions stay literal.
- Both folder-drag trust refusals now resolve through the app catalog before
  entering the shared error presentation.
- TextSearch's malformed-path and retained-external-change errors now resolve
  through TextSearch's package catalog before the app displays their messages.
- A theme export's empty-name fallback uses the existing app `Theme` key.

French, Japanese and Polish values added here are English `needs_review` drafts.
No translation acceptance or native language/layout result is inferred.

## Guard and evidence

`plain-string-sink-ledger-2026-11-09.json` binds 66 selected literal routes
across 21 source files to their SHA-256 source bytes. The checker enumerates
all 742 first-party production Swift inputs and rejects changed or newly
unclassified selected AppKit property/button/accessibility, filename fallback,
folder error and workspace-replace error routes. Four additional source or
metadata areas are marked `open` for a wider audit; their hashes identify this
snapshot but do not count as clearance. CI runs the guard and its
negative controls alongside the existing catalog and compiler checks.

Locally, four guard controls pass; catalog/Transifex structure checks pass for
15 catalogs and 699 entries; changed Swift parses; strict SwiftLint, SwiftFormat
and diff checks pass. Xcode 26.6's `xcstringstool` compiled the three affected
catalogs into 12 locale resources. Readback found 27 expected key/locale
routes. `Theme` uses its source-English fallback because its existing catalog
has no explicit English unit. No application or native UI ran in this account.

## Remaining E16 audit

The selected-sink scanner is deliberately not a Swift parser or dataflow
analysis. The complete census still needs typed review of computed UI values,
SwiftUI implicit localization, built-in snippet names, technical file-format
labels, bundled theme names, Finder-visible metadata from `project.yml`, and
user-authored/protocol exceptions. The existing compiler stringsdata check
proves positive catalog coverage for extracted keys but does not discover
plain Strings. After source classification and fixes, the isolated test desktop
must verify real AppKit and accessibility language sentinels. Translation
quality, pseudo-localization, and the exact final freeze remain separate gates.
