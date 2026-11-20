# Private save staging before publication

## Owner summary

Saving an existing readable file copies its permission bits and access-control list (ACL) onto a replacement before the replacement becomes the document. A same-folder temporary file can therefore expose the new text during that preparation interval. This change puts the temporary file inside a newly created private folder on the destination volume. The folder drops any ACL inherited from its parent before the temporary file is created. The final file still receives the existing destination metadata before the atomic replacement.

This is a source and local-filesystem remedy for the preparation interval. It does not substitute for the deferred cross-account native privacy and full save/recovery acceptance in issue #17.

## Baseline and behavior

- Base: `91bde1b1309a6a1da396ef063306f27c366e698c` on MostlyText `main`.
- `FileStoreStage` already creates a regular file with mode `0600` before writing its bytes. Conditional saves then call `carryMetadata`, which can set that file to the destination's readable mode and ACL before `RENAME_SWAP`.
- The new directory uses exclusive creation, mode `0700`, a no-follow open of the created entry, and an empty extended ACL before the stage is opened. It stays on the destination volume so the existing exchange, no-exchange fallback and unconditional replacement algorithms retain their publication semantics.
- A successful publication or safe rollback leaves the directory empty; cleanup checks the directory's original physical identity before attempting empty-directory removal. A changed stage or displaced external file remains at its reported recovery path inside the private folder. The final unlink is path-based, so a hostile rename of the parent remains outside this source-level proof.
- Volumes that do not enforce POSIX permissions cannot gain cross-account confidentiality from permission bits. The existing non-exchange fallback remains supported; its privacy behavior remains a native acceptance question.

## Verification and limits

- The new readable-destination test inspects the prepared stage before publication: the final file's `0644` bits have been copied, while the containing directory is `0700`. It checks the published bytes/mode and absence of a leftover folder.
- A second test adds an inheritable `everyone` ACL to the parent and verifies that neither the private folder nor its stage inherits that entry. Existing conditional/unconditional, metadata, Save As, unsupported-exchange, rollback and retained-recovery tests continue to run.
- The first local build was interrupted because a test source was edited during compilation. The next focused run found two recovery assertions that still searched for direct sibling files; their preserved files had moved inside the private folder. After those assertions were updated, the FileStore selection passed 57 tests in nine suites. The combined Debug and optimized Release selections each passed 113 tests in 13 suites, including FileDocument and Workspace Save As paths. Logs: `/private/tmp/mostlytext-private-stage-filestore-test.log`, `...test2.log`, `...test4.log`, `...focused-final.log`, and `...focused-release.log` on the author machine.
- Cross-account read denial, Finder moves, network/removable filesystems, whole app lifecycle and the formal private verification candidate remain open under #17/#12. No native checkpoint was launched.
