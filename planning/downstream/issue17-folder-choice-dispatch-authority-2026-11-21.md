# Folder choices retire old search state at dispatch

## Owner summary

Opening a folder changes the window's chosen root immediately, but the file tree and search index previously began their root transition only when a newly scheduled task happened to start. A second folder choice or existing-file focus could overtake it. In the gap, the old Quick Open and folder-search publication could still appear current, and a late first task could load the superseded root.

The window now reserves a root request synchronously when Open Folder, session restore, existing-file focus or the Reveal Active File parent-folder sheet chooses it. This immediately retires old search actions. A queued task applies its root only if that request and the model's folder association are still current. The direct root API retains its existing generation and supersession checks. Existing-file focus also stops after a superseded root rebuild instead of applying an old sidebar selection.

## Scope and verification

- This batch is based on document-action PR #319 head `b8e3a40c7e14350494ab57e934629ee1df051ad1`, merged into main as `2a1c6ce3fd873c73e738813ab16597921ddabeb8`. The merge tree exactly equals that tested head tree. This folder diff remains separate and awaits its own hosted app tests.
- Direct issue owner: #17's F18/F19 navigation and lifecycle audit. #6/#8 consume only eventual complete evidence; their broad rows remain open.
- Four controlled app regressions cover an old queued request after a newer direct root, synchronous retirement of stale Quick Open and search, repeated same-folder choice, and an existing-file focus overtaken during root loading. They inspect actual tree/index/selection state, not only token equality.
- SwiftFormat, strict SwiftLint, ordinary compliance, selector unit tests, sink audit, and a locked Debug app/test-bundle build pass after rebasing onto #319. The build does not launch the app. App-test execution belongs on hosted macOS CI; the protected interactive native checkpoint remains owner-deferred.
- The selected plain-String sink review still finds the same 68 literal/route pairs across 791 production Swift inputs. Two touched source hashes were updated after verifying that no sink or route changed; the sink audit passes. This does not replace the full localisation/native layout review.
- The reviewed selector classifies the nine changed paths as `app-only`: the full app suite and locked app builds run, while unchanged package tests are omitted. Hosted execution remains pending until this branch is submitted after #319.
- No document text, on-disk folder contents, bundled resources, localization strings, dependencies or public release settings change.
