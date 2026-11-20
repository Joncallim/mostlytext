# Encoding choices stay with their originating document

## Owner summary

Choosing **Save**, **Save with Encoding** or **Reopen with Encoding** starts asynchronous work. A menu choice could be queued before its task began, then act on a different document after a tab change. A status-bar choice was routed to its owning window, but its closure could also outlive the document displayed when the bar was rendered. Reopen checked file and recovery identities after reading disk, yet a newly selected tab exposing the same document value could still pass those checks.

This change binds each choice to its originating tab, document recovery lifetime, and active-identity revision. The status bar only publishes the encoding control when its displayed tab/document matches that captured authority. The action rejects stale work before queuing, after recovery drain, and before applying a completed disk read or confirmation. Ordinary Save also avoids presenting a destination picker for a replacement document. The existing same-encoding no-op and safe save/reopen behavior remain in place. No document bytes, preferences, bundled resources, dependencies, or release settings change.

## Baseline and scope

- Baseline: `2e120d728c9b4bca67f74472bf950aa15ec51bff` on `main`.
- Direct owner: MostlyText #17 R01 and F17; #12's external-file lifecycle shares the reopen path.
- This is an app-action lifecycle repair. It does not establish the historical #19 parser trigger, #18 visible-paint budget, or #12's whole interactive matrix.
- The protected native checkpoint remains owner-deferred. No owner desktop app launch or signed candidate is claimed here.

## Verification and later checkpoint

The app regressions cover a queued Save choice followed by document replacement, a stale Reopen choice, and a new tab showing the same dirty file/recovery lifetime while a discard confirmation is pending. The latter keeps the user's text and returns a superseded result. Existing encoding-origin, no-op, disk-change and recovery tests remain part of the selected app suite.

Compile the locked Debug app and test bundle without launching it locally. Hosted checks run the selected app tests, locked app/CLI builds, lint, and compliance. The later protected native checkpoint should choose encodings from both menu and status bar while switching/closing windows and editing a dirty file; verify the selected document, disk bytes, undo state, and prompt ownership. This source repair is not a substitute for that observation.

The same PR teaches CI to skip package test execution for app-only diffs while retaining every app test and locked app/CLI build. A mixed app/package change runs the dependent package tests and all app tests. The selector and workflow themselves change in this PR, so its own validation intentionally falls back to the complete package-and-app lane. The selector's 15 local unit tests pass. An initial local YAML parse command could not import the optional Python `yaml` module; Ruby's installed YAML parser loaded the unchanged workflow structure and amended condition successfully.

The first hosted inventory job on commit `dd161874` failed because the selected plain-string sink ledger pinned line positions and source hashes in two edited controller files. The `--discover` comparison found the same 68 literal/route pairs, no additions or removals, seven shifted lines in `WindowController+Encoding.swift`, and changed bytes only in that file and `WindowController.swift`. The reviewed ledger now records those positions and hashes; the local sink audit passes with zero plain exceptions and four retained deferred reviews. This correction does not claim the full E16 string audit.
