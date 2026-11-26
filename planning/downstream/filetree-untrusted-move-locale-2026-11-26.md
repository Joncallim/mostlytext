# File Tree drag refusal follows the presenting language

An internal drag can be rejected after its trusted token expires or the root
changes. Both sidebar drop targets previously stored a `String(localized:)`
value in `FileTreeOperationError.underlying` when the operation happened. The
alert is rendered later through `message(locale:)`, but `underlying` returns
its stored string unchanged. A language change between those points could
therefore leave the refusal in the earlier language. The refusal now has a
typed `untrustedMove` case; FileTree resolves its catalog text for the alert's
locale. The authored detail retained by `underlying` is still passed through.

The same change moves this key from the app catalog to FileTree's package
catalog and refreshes the source inventory. French, Japanese and Polish values
remain English review drafts; this is routing proof, not translation approval.

The selected plain-string sink checker formerly accepted a changed file in
`deferred_review` because it verified existence but not the stored SHA-256. A
new negative control first failed with `AssertionError: ValueError not raised`.
The checker now rejects changed deferred bytes. The two stale current-main
fingerprints for `Snippet.swift` and `project.yml` were reviewed and refreshed;
all four deferred reviews remain open.

Local verification: pinned Debug FileTree selection, 93 tests/10 suites;
QuickLookSourceFallbackTests, 13 tests/one suite; five sink-audit unit controls;
catalog inventory/Transifex-coverage and Finder type-label static checks;
strict lint, format and ordinary compliance; pinned Debug app and test-bundle
`build-for-testing`. The new locale case also passed alone. The build compiled
the app/tests but did not execute app or UI tests. Protected installed-app
language/drag observation, translation quality, full E16 audit and final
string freeze remain open under issue #3. Exact-head hosted results belong to
the PR and issue evidence, not to this local build.
