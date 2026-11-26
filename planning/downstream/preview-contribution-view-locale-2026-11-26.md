# Preview contribution language selection — 26 November 2026

## Owner summary

Preview's contribution badge already names its count in the window's language, but the messages opened from that badge were created using the process language. This change gives the same selected language to the contribution producer, its admission and budget diagnostics, and the published Preview snapshot. Changing language recomposes the contribution; while that work is pending, Preview shows the unchanged authored blocks rather than an old-language generated placeholder.

The source text, source ranges, placement rules, budgets, export output, and diagnostic severity are unchanged. Package-owned table-of-contents copy still has draft non-English catalog values, so this change selects the correct package catalog but does not claim completed translation review.

## Scope and evidence

- The selected locale is part of `PreviewContributionTaskID`; a language change invalidates an old publication even when the parser revision is unchanged.
- App-owned rejection and budget strings resolve from the selected app localization. Package-owned table-of-contents and registry strings resolve from the selected Contributions localization. Producer free text remains verbatim.
- Focused tests cover a French app-owned rejection, English comparison, unchanged authored blocks, and the old-language publication fallback. The package's 40 contribution tests pass with the committed dependency lock.
- A pinned Debug app/test `build-for-testing` compiles the affected app boundary. This does not execute the installed app or replace the protected native language/layout checkpoint.
- The first [hosted Release viewport run](https://github.com/Joncallim/mostlytext/actions/runs/45754771098) executed 65 tests in 18 suites, including the new language-handoff case, but the exact-result verifier still expected 64. Its [artifact](https://github.com/Joncallim/mostlytext/actions/runs/45754771098/artifacts/15089610424) and first-failure log are retained. The verifier now requires 65 Release and 64 Debug tests and explicitly names the new case. This adjusts the receipt to the actual expanded suite rather than removing a test.

The original whole-app string audit, native non-English and pseudo-localized layout journeys, translation review, and final string freeze on issue #3 remain open.
