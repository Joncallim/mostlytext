# FileStore save-stage creation permissions — 19 November 2026

`FileStoreStage` is the same-directory temporary file used by ordinary Save and
Save As. It previously called `openat(..., 0666)`. With the ordinary `022`
umask, the stage was `0644` while authored bytes were being written. A failed
write could also retain a partly written stage under those permissions.

The stage now starts `0600`. This changes a newly created destination to
owner-only permissions. Replacing an existing destination still copies its
permission bits, ACL and extended attributes through the existing conditional
publication path; those established behaviors remain under their tests.

The new direct stage test failed on the old source under umask `022`: observed
`0644`, required `0600`. With the creation-mode change, the focused stage and
metadata suites pass 14 tests in two suites, including exact new-file mode,
existing `0600`/`0644`/`0755` modes, ACL and xattr retention, and adverse
retirement cases. The wider focused FileStore selection passes 55 tests in
nine suites, including conditional publication and failed-stage preservation.
The local test host is macOS 14; hosted macOS 26 checks are required before
integration.

This is source and filesystem evidence for the first-byte stage permission.
It does not prove a complete cross-account native privacy matrix: the existing
metadata-copy path may deliberately apply a readable destination's permissions
to the stage shortly before publication. The larger #17/#8 release review and
protected candidate checks remain open.
