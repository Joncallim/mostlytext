# Private printer scratch for ordinary PDF export

AppKit's `NSPrintOperation` requires a file URL for its `.save` disposition.
Previously the adapter generated a random-looking file beside the user's
chosen PDF and unconditionally removed that path on exit. A foreign object at
the guessed or replaced leaf could be deleted, and the intermediate print was
visible in the export directory.

The adapter now creates one `0700` directory beneath the app's temporary
directory and hands AppKit only `print.pdf` inside it. The directory's open
descriptor and device/inode are retained. Reads use a bounded `openat` with
`O_NOFOLLOW` and pre/post file identity checks; the chosen export admission is
used only for final atomic publication. Retirement uses the pinned descriptor
and removes only the regular single-link printer leaf, then the empty owned
directory. A symlink, extra object or changed directory is left for conservative
recovery. The vector snapshot fallback already returns memory bytes.

The first hosted Release menu run (43321978646) reached PDF Export but showed
an `Export Failed` sheet with `No such file or directory`. The first genuine
pagination run (43321978832) independently failed four PDF tests at private
scratch construction with the same error. The system may advertise a sandbox
temporary directory before creating it. The adapter now creates that
OS-provided base when needed, then requires an owned, private, non-symlink
directory before `mkdtemp`. A focused missing-base regression passed locally
along with the three existing scratch safety tests. The original failed runs
remain failures; a fresh hosted app and pagination pass is required.

This removes the printer's public sibling pathname without assuming AppKit can
print directly into an unlinked descriptor. It does not claim exclusion of a
malicious process running under the same user ID, nor does it prove the final
signed candidate's full export latency or cancellation behavior. Focused tests
cover private permissions, bounded read/retirement and symlink refusal; the
hosted ordinary Release app export and PDF pagination jobs must pass at the
exact merge head.
