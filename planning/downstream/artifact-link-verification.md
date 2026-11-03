# Verify artifact links without hiding distributed resources

## Owner summary

The release compliance check currently skips symbolic links. A complete passing
app fixture can therefore carry an unregistered external script or resource tree
without failing. Reject escaping, broken and cyclic links and unsupported filesystem
objects; account for internal file aliases under their distributed names. Preserve
normal relative framework links and the installer-level Applications shortcut.
This strengthens MostlyText #14 / #4 verification without changing the product,
notices, dependencies, native hold or any unresolved release predicate.

## Baseline and contract

Baseline main 8b56e30e292874b09b0e827212a70adad6e4c3e9. The current walker ignores
both file links and directory links. Two real filesystem fixtures, each with all
required resources plus one outside file/directory link, incorrectly return zero
strict errors. Artifact resources are deliberately matched by digest rather than
fixed destination path. Preserve that rule and all existing source/notice checks.

Only compliance/tools/compliance.py, its fixture tests and current compliance/
acceptance documentation change. No app execution, signing, publication or dependency
changes. Operate on owned fixture directories and existing compile-only products.

## Link and filesystem policy

Resolve the supplied artifact directory once. Inspect file and directory entries,
including dangling links, and report unreadable walks/stat/hash errors as failures.
Do not descend into symbolic directory links. Each link must have a relative target,
resolve to an existing ordinary file or directory inside the artifact and be free
of cycles. File aliases count under their alias path and resolved file digest, so
an unknown text file cannot evade the registered-extension rule via a .js alias.
The real internal target is also scanned normally. A directory alias needs no
second traversal; its internal target is covered by the complete real-tree walk.

The single installer exception is a root Applications link whose literal target is
/Applications, outside a .app or a root with Contents. The release DMG assembler
creates this exact installation shortcut; it is not a runtime resource and is
never traversed or hashed. No nested or differently spelled escape receives that
exception. Reject special filesystem nodes rather than opening a pipe/device.

The check expects a stable prepared/signed candidate, not a hostile concurrently
mutating tree. It does not establish a race-free filesystem snapshot, code-signature
validity, complete binary attribution or final release acceptance. Missing resources,
remaining independent review, six strict findings and native gates remain failures.

## Verification and completion

Add failing-before tests for external file/directory links, an unknown internal
file disguised by a script alias, dangling/cyclic/absolute links, special nodes
and refused scans/reads. Positive controls retain a versioned-framework directory
alias, a registered internal resource alias and the exact installer shortcut;
nested/fake shortcuts fail. Test a supplied root through a filesystem alias and
failure on a non-directory artifact. Run all compliance and preflight controls,
verify actual compile-only app artifacts, deterministic notice/SBOM bytes and
unchanged runtime/pins. Hosted exact-head Compliance and reviewed merge-tree proof
precede merge. Update issue source criteria without closing whole acceptance gates.
