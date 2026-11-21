# File-tree writes remain inside the selected folder after a child moves

## Owner summary

Creating, moving or copying a file in the sidebar could write outside the
selected folder if another process moved its destination directory after
MostlyText opened that directory. The earlier protection rejected links that
were already visible, but a held directory handle followed the moved object.
This change stages new content at the selected physical root and resolves the
final source and destination from that root in one macOS rename that refuses
symbolic-link traversal. The affected operation fails when the old child path
has become a link or disappeared.

This is a scoped file-tree safety repair under issue #17. It does not change
the Finder Trash path or Replace in Folder's separate `FileStore` publication
path, and it does not stand in for the deferred installed-app test.

## Baseline and controlled failure

- Current-main parent: `64fd7e71e19b0f61cc0c871a0bb1b17a31e6abc0`.
- Test-only scaffold: `d8440ef3`. It moves `root/dir` to `outside/dir` and
  places a link at the old name after the mutator has opened the child parent.
- On that exact scaffold, the focused five-case test failed with ten issues:
  Create File, Create Folder, Move into the child, Move from the child and Copy
  into the child could complete through the held parent outside the root.
  The complete output is retained as `failing-before-d8440ef3.log` in
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-root-relative-mutations-20261121/`.

## Implementation and boundaries

- Validate lexical components and retain the selected root's device/inode as
  before. Do not split a joined path with Swift `Character` semantics: a slash
  before a combining mark must remain a path boundary.
- Create File, Create Folder and Copy use unique private stages at the root.
  The final `renameatx_np` uses the root descriptor for both names with
  `RENAME_EXCL | RENAME_NOFOLLOW_ANY`. Move uses the same final root-relative
  operation without a stage. A symlink file itself can still be renamed.
- No stage or destination is published after the controlled child relocation;
  the source of a refused move stays where the external process moved it.
  Failed creation/copy cleans its private root stage in the tested cases.
- A selected root that is not writable cannot host a private stage even if a
  nested child is writable. A nested mount on another volume cannot receive
  the atomic rename. These conditions fail closed rather than writing through
  a moved child. The selected root's physical object remains the authority if
  its lexical path changes after the initial identity check.
- This repair addresses outside-root publication at the final filesystem
  operation. It does not make a non-cooperating writer's concurrent directory
  replacement an atomic version comparison, and it does not close the broader
  F14 family by itself.

## Verification

The seven focused tests pass in Debug and optimized Release, including the
fifth moved-source case, combining-mark path-boundary control and explicit
read-only-root refusal. The complete FileTree Debug selection passes 90 tests
in nine suites on the local macOS 26 host. Strict SwiftLint, SwiftFormat,
`git diff --check` and ordinary compliance pass.
Strict release compliance retains the ten existing issue #14 source/provenance
failures; this FileTree change adds no dependency or bundled resource.

Retained local logs under the directory named above have SHA-256 digests:

| Record | SHA-256 |
|---|---|
| `failing-before-d8440ef3.log` | `294bad2a19904a49401c1db240b5b9ca3bba3e508058e70bebb9d2035ff371bf` |
| `passing-after.log` | `b29a6ebde7a804e4aee816cb4bea0ae6860921d81ebb765f255059d31e691e9d` |
| `release-focused.log` | `494f9ca9e1e1ca4b2a43bcca633f30bf1f15671eae410ffd021bf7b25b4ffbdd` |

Hosted PR checks and the exact final source identity will be recorded on the
issue after they finish. The protected interactive native checkpoint remains
deferred by the owner.
