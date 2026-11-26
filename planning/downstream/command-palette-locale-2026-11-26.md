# Command palette language follows its window

## Owner summary

The command palette cached its twelve built-in titles when the process first
loaded them. A later palette window could therefore keep names from a different
language, and its user-command accessibility label independently used the
process language. This change resolves both when the palette is presented.
Command IDs, available actions, user-authored script names and search behavior
remain the same; search now sees the titles actually displayed in that palette.

## Baseline and approach

Starting from `main` `76351dc37c3e69598e8e9b7b59a74ff6e5bb0163`, the app's
catalog already contains all twelve built-in titles and the user-command
accessibility key. `CommandPalettePanel` owns the AppKit window and creates the
model and SwiftUI host. It selects the app bundle's preferred language at that
boundary, constructs fresh localized command titles and gives the hosted view
the same locale. The row keeps a discovered text filter's authored name literal
while localizing only the surrounding accessibility phrase. No catalog keys,
translations, command authority, persistence or document content change.

## Verification and limits

The multilingual app test bundle has distinct English and French values for
every built-in title and the accessibility phrase. It checks stable command
IDs, the French open/folder titles, search against the displayed language and
literal user-script names. A compiled-app lookup checks the shipped French
`New File` value. Existing palette command, targeting and catalog
consistency tests remain the action/availability controls. The PR records the
final source identity and exact-head checks.

This is a source-level localization correction under MostlyText #3. Protected
installed-app language, VoiceOver and pseudo-localized layout observations
remain deferred. The whole-app string audit, translation review and final
string freeze are separate issue criteria.
