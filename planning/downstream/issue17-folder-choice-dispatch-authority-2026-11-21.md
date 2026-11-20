# Folder choices retire old search state at dispatch

## Owner summary

Opening a folder changes the window's chosen root immediately, but the file tree and search index previously began their root transition only when a newly scheduled task happened to start. A second folder choice or existing-file focus could overtake it. In the gap, the old Quick Open and folder-search publication could still appear current, and a late first task could load the superseded root.

The window now reserves a root request synchronously when Open Folder, session restore, existing-file focus or the Reveal Active File parent-folder sheet chooses it. This immediately retires old search actions. A queued task applies its root only if that request and the model's folder association are still current. The direct root API retains its existing generation and supersession checks. Existing-file focus also stops after a superseded root rebuild instead of applying an old sidebar selection.

## Scope and verification

- Main baseline before this local batch: `2e120d728c9b4bca67f74472bf950aa15ec51bff`. This branch is held locally until the document-action PR #319 merges, then must be rebased and revalidated.
- Direct issue owner: #17's F18/F19 navigation and lifecycle audit. #6/#8 consume only eventual complete evidence; their broad rows remain open.
- Four controlled app regressions cover an old queued request after a newer direct root, synchronous retirement of stale Quick Open and search, repeated same-folder choice, and an existing-file focus overtaken during root loading. They inspect actual tree/index/selection state, not only token equality.
- SwiftFormat, SwiftLint and a locked Debug app/test-bundle build are source/build checks. App-test execution belongs on hosted macOS CI; the protected interactive native checkpoint remains owner-deferred.
- No document text, on-disk folder contents, bundled resources, localization strings, dependencies or public release settings change.
