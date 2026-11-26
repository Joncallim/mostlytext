# Math Preview language follows the window

## Source finding

The math Preview's notices, equation accessibility labels, source actions and
the neighboring contribution warning/error badge used the process locale. A
SwiftUI Preview window can receive a different selected locale. Rebuilding
only its surrounding view left generated math content and the badge's accessible
count in the previous language.

## Change

The Preview passes its environment locale through the existing source planner
and native presentation builder. A locale-identifier change restarts only the
presentation task; the source analysis and equation ranges remain authoritative.
The notice button and contribution badge resolve their accessible wording in
the same locale.
Other package callers retain their existing process-locale defaults. No new
catalog key or translation is introduced.

## Verification and limit

The app test reuses one parsed/evaluated source across English and French
presentations, checks the compiled package strings for equation labels,
actions, notice wording and title, and compares source locations. Final test
and commit identities are recorded on the PR. Existing translations marked
`needs_review` remain drafts. A protected installed-app language and VoiceOver
observation remains deferred under MostlyText #3 and #9.
