# Present panel and status copy in the view language

## Owner summary

The export panel, HTML preview switch, external-file warning, theme picker and
reduced-highlighting note should use the language of the view displaying them.
These controls already have catalog entries, but several build a plain `String`
without passing SwiftUI's selected locale. The change routes that locale to
those existing entries and formats the highlighting threshold in the same
language. It does not change file operations, search, preview/export output,
theme selection or the highlighting size policy.

## Baseline and scope

Current `main` at intake: `80d907055193af3e07b44a1d885bb3b063949c4b`.
The previous #3 repair covered Find and Folder Search. This batch covers five
other app views whose displayed strings are converted to verbatim `Text`,
accessibility help or an AppKit accessory. The catalog keys and values remain
unchanged. Xcode's source extractor reports zero added and zero removed keys
for the five changed view files compared with the intake revision.

The view owns its environment locale. Small pure copy functions accept that
locale and an injectable bundle for focused tests; defaults continue to use
the app's bundle. The external-file issue categories and authored details are
unchanged. The highlighting threshold remains 6,144 UTF-16 units for Markdown;
only its grouping separator follows the presented locale.

## Verification and remaining work

A disposable French test bundle gives distinct translations to the export,
preview and external-file messages, proving that the selected locale reaches
each displayed copy route. A separate test compares French and English number
grouping in the highlighting help. Pinned local app/test-bundle compilation,
catalog extraction, inventory, strict lint and final-head hosted app tests are
the code gates. Installed language/layout and pseudo-localization acceptance
remain deferred under #3; this source repair does not close those criteria or
declare the final string freeze.
