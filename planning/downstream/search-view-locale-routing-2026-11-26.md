# Find and Folder Search language routing

## Owner summary

When a language is selected for a SwiftUI view, its search status and help text
should use that same language. Folder Search already passed the view locale to
its count messages, but skipped-file reasons used the system locale. Find did
the same for option help and two search errors. This change passes the view
locale through those remaining app-owned messages. It leaves document text,
file names, regex diagnostics supplied by the search engine, and stored search
state untouched.

## Scope and evidence

Baseline: MostlyText main `a9b9957594b50a890f61df46fa3fb3a8ca72273b`.
The app catalog already contains all affected keys, so no new translation
entry or wording is introduced. The focused regression uses a disposable
French resource bundle with distinct values for six skipped-file reasons and
two Find errors. It checks both selected-locale routing and the verbatim
treatment of authored failure text. The existing count/plural tests continue
to cover the neighbouring Folder Search messages.

The Find option labels and help use the same explicit locale argument at their
display sites. The final E16 string audit, translation quality, pseudo-layout
and interactive non-English acceptance remain open in MostlyText #3. These
source checks do not claim a native language pass or a final string freeze.
