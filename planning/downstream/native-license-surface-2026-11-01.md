# Offline About and license surface

## Owner outcome and baseline

From About MostlyText, open the first-party MIT license and the complete generated
third-party notice corpus locally, with native text selection, copying and Find.
Do not maintain another notice copy, render authored HTML or fetch a website.
Baseline integration is `1b79485699199509ec15e0baa34906e5ffd4b63e`; master is
`15c0fae22f7618e94c82681227057c66011be2a9`. #148 LC-08 and its handoff own this
surface. The project already bundles LICENSE and THIRD_PARTY_NOTICES.md directly
from their canonical tracked paths; keep those resources and original texts.

## Ownership, behavior and limits

The app owns two non-document SwiftUI windows, About and Open Source Licenses.
The existing non-document close route remains unchanged. The About menu opens
About; its license button opens one reusable license window. About states the
frozen MostlyText name, MacDown lineage and MIT terms, without a EULA. Bundle
version/build are informational; no runtime identifier or state migration changes.

A segmented control selects the first-party license or third-party notices.
An AppKit read-only, selectable NSTextView provides wrapping, native Find, Copy
and accessibility text. The existing single Cmd-F command routes through the
focused license action while that scene is active; no competing shortcut is
registered. No web view, Markdown/HTML execution or automatic links
are used. The surface has no document, workspace, recovery or settings model.
Window restoration is disabled for both informational windows.

Read only the two fixed resources from the application bundle. Bound each read
to 2 MiB plus one overflow byte, reject invalid UTF-8/empty/missing/oversized
resources and show a localized failure instead of a truncated or fabricated
notice. Do not rewrite original license text. Opening the screen is an explicit
user action; local bounded resource loading has no background poll or network.

## Verification and completion boundary

App-target tests verify the loader's missing/invalid/oversized behavior, canonical
tracked-vs-bundled bytes, and read-only/selectable/no-link text configuration.
Strict lint/format, Compliance and full hosted app/package/Release builds apply.
Add surrounding UI to the existing catalog in English, French, Polish and
Japanese. Translation drafts still require the existing final native review.

Before LC-08 closure, the isolated desktop must demonstrate About -> both texts,
Find/Copy, keyboard close and focus, VoiceOver/readability and failure disclosure.
Before release, repeat resource/hash checks against the exact final signed
artifact. This implementation does not publish corresponding source, complete
LC-01–LC-10, replace final language review or close #148/#115 by itself.
