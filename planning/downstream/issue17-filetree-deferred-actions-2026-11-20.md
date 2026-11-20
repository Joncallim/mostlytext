# Keep delayed sidebar actions on their originating document and folder

## Owner summary

A folder read or confirmation sheet can finish after the user switches documents,
changes folders, or edits the text. In that case, MostlyText must not apply the
old action to the new document. This pass binds two sidebar actions to the state
that started them: Reveal in Folder and the choices after a file is moved to
Trash. It preserves document bytes and recovery lifetime when a result is
stale. It adds no new permission, network request, string, or file format.

## Baseline and failure

The source baseline is main 20ab15066c6dd6ab8d675d611eba7c59dc9c6ac5.
The FileTree model's reveal awaited directory expansion and then selected a
matching URL without rechecking the root generation. A controlled A to B to A
replacement, with the older A read held until the new A published the same
path, returned true and selected that new path from the old request. The new
test failed both expected assertions against the unchanged baseline.

The app's deleted-file sheet saved the tab named by the prompt but discarded
the window's current active document. The response could therefore retire
unrelated recovery after a tab or document replacement. It also lacked a
check for later edits or a renewed recovery lifetime. The Reveal alert could
change the sidebar root after its originating document or folder changed.
These are source-level lifecycle findings; no claim is made that a user
encountered them in the final app.

## Repair

- FileTree reveal checks its captured root generation after each suspended
  expansion and before selection.
- The app captures the document, tab, window, recovery lifetime, and presented
  content for the deleted-file sheet. Save As and Discard act only if those
  still match. Discard rechecks immediately before retiring recovery.
- Reveal checks the originating document, window, and root generation before
  showing or accepting its alert. After changing the root, it checks the exact
  root request before selecting the file.

A stale sheet result becomes a no-op; the user can invoke the command again
against the new state. No existing source or recovery file is changed by
that refusal.

## Focused evidence

The same controlled FileTree test failed on unchanged main (stale selection)
and passed with the guard restored. The selected FileTree run passed 72 tests
in 7 suites. A locked Debug app and test-bundle build passed; it did not
execute the app or open a desktop window. The first local build command
failed because it supplied an invalid Xcode option; a later compile found a
missing FileCore import in the changed file. Both were corrected before the
successful build. Strict changed-file lint, format, Swift syntax, and diff
checks pass.

The first hosted compliance run on 5f034dbf failed the selected-string sink
ledger because this file's reviewed localized strings moved to new line
numbers. Discovery found the same 13 localized literals, with no new plain
route. The ledger now records their new lines and source hash; its focused
tests and check pass with 789 first-party inputs, 68 selected sinks, zero
plain exceptions, and four already deferred reviews. No translation claim
is inferred from that source check.

The exact focused logs are retained as compressed files in
evidence/issue17-filetree-stale-actions-2026-11-20/:

| Log | Compressed SHA-256 |
| --- | --- |
| baseline-failure.log.gz | 053780f052bd494fdd67f8c157ca8611792e79356c043252369b785590bdcbd1 |
| fixed-replay.log.gz | c18ecb2ad25405acd0bd4a92da1a03bfc1b351147971b0bbede4e243cc70f37b |
| filetree-suite.log.gz | f8eb0ba212868c29b6f1dbb4f5b9f1fd54ee9a1e75deda02ae52ec50944b03c1 |
| app-test-build.log.gz | 759028336a1d341a766904ff8e6d5b5b2187500c8601edee254cfd284681289d |

The app regression tests cover the ordinary discard, replacement active tab,
later edit, renewed recovery lifetime, and Reveal's document/root changes.
Hosted app execution and final native interaction remain to be recorded. This
is a scoped #17/#8 review repair, not closure of either broad issue or #12's
candidate/manual matrix.
