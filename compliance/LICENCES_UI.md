# Open Source Licenses window (LC-08)

The read-only license window is implemented. About and the application menu
open the shared licenses scene; its two documents are the bundled MostlyText MIT
license and generated third-party notices. The implementation uses a native plain
text view, preserving wording and enabling standard Find and Copy without active
markup, automatic links or a network content source. It does not use the Markdown
preview renderer. This supersedes the old unstarted/Textual design.

## Source contract

- `MacDown2/MacDown2/AboutCommands.swift` supplies About and license entry points;
  `MacDown2App.swift` registers the shared scenes.
- `LicenseNoticesContent.swift` loads only `LICENSE` and `THIRD_PARTY_NOTICES.md`
  from the selected bundle. Each resource is bounded at 2 MiB; empty, invalid UTF-8,
  missing and oversized resources fail. No source-tree or network fallback exists.
- `LicenseNoticesView.swift` switches the two documents, exposes read-only selectable
  native text, and routes Find through `FocusedLicenseFind.swift`. Automatic link
  detection and editing are disabled. Labels and surrounding strings use catalogs;
  original third-party texts are not translated.
- `project.yml` copies the canonical root license and generated notice file into
  the app. `compliance.py check --artifact` requires both exact byte sequences.
- Failure presents the localized bundled-text loading error. It does not assert,
  open a web page or substitute an unrelated resource.

## Evidence and remaining acceptance

`MacDown2Tests/LicenseNoticesTests.swift` covers decoding/limits, expected bundle
contents and native text-view configuration. The final whole-app CI and exact
resource evidence are linked in [acceptance status](../planning/ACCEPTANCE_STATUS.md).
A separate exact-source Foundation-only control has loaded the generated notice
corpus from a compile-only Release app; that proves neither visible UI nor VoiceOver.

The original LC-08 contract also requires a Help-menu entry. Current source
registers only About and the application-menu entry, so Help integration remains
an implementation item under #14; this documentation does not waive it.

Before LC-08 closes, obtain the protected-account Release journey: open from both
implemented entry points, reopen/raise the shared window, switch documents, Find/Copy/scroll and
close with the keyboard, and verify VoiceOver labels and readable localized layout.
After final localization, repeat affected paths and exact resource checks on the
signed/notarized candidate under MostlyText #4/#14. No passing component test or
compile-only build substitutes for this native or exact-artifact evidence.
