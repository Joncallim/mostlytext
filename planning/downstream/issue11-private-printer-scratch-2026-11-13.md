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
scratch construction with the same error. Materializing an absent sandbox temp
base passed a local regression but did **not** fix the hosted condition:
ordinary run 43326546974 and pagination run 43326546981 repeated the same
failure. All four pagination tests failed at direct scratch construction, so
the failure remains before AppKit printing or final publication.

The next revision pins the OS-provided temp base descriptor and uses `mkdirat`
and `openat` for the private child. It retires the directory relative to the
same pinned base, with a path/identity check before reads and retirement.
Setup failures now name their boundary and POSIX code without revealing the
temporary pathname in the user alert. This replaces the path-based `mkdtemp`
assumption, but the exact hosted cause is still unclassified until a fresh
run succeeds or the new stage error identifies it. Four local scratch tests
pass, including the missing-base and symlink controls. Both previous hosted
failure pairs remain failures.

This removes the printer's public sibling pathname without assuming AppKit can
print directly into an unlinked descriptor. It does not claim exclusion of a
malicious process running under the same user ID, nor does it prove the final
signed candidate's full export latency or cancellation behavior. Focused tests
cover private permissions, bounded read/retirement and symlink refusal; the
hosted ordinary Release app export and PDF pagination jobs must pass at the
exact merge head.
