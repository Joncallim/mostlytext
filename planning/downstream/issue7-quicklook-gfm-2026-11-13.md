# Static GFM in the bounded Quick Look worker

The production source shell is already a separate sandboxed worker with an
input cap, process deadline and one-shot extension reply. Its literal `<pre>`
view is useful as a failure fallback, but it does not satisfy Quick Look's GFM
structure criterion.

`QuickLookSource` now consumes `ExportService.renderPassiveMarkdownFragment`.
That public helper uses the same cmark-gfm bridge and extension registration as
ordinary HTML Export. It runs in the existing worker child, with no new parser,
parent-directory grant or containing-app launch. The passive option blanks
every authored link and image URL; raw authored HTML is not enabled. The reply
still has `default-src 'none'`, no base URL and the existing 4-second extension
settlement. If the renderer refuses nonempty source or expands beyond the
6 MiB plus framing cap, the worker returns the escaped literal source view.

The app-host test bundle compiles the shipping worker process controller to
exercise descriptor and deadline behavior. Linking all of `QuickLookSource`
there also linked `ExportService` through a second product path, and the first
full CI run saw 17 cross-image `ExportError` type-identity failures. The XPC
status and shared byte caps now live in the small `QuickLookBoundary` product.
The process controller and app-host tests link that product alone; the real
provider and worker link both boundary and source renderer. This keeps the
shipping process checks while preserving one export type identity in app tests.

Focused tests cover GFM table/strike structure, URL removal, raw active HTML
refusal, injected renderer refusal/oversize fallback, strict decoding, exact
1 MiB admission, a selected descriptor whose path is replaced, and named-pipe
refusal. The package test result alone does not qualify the installed provider.
Exact-head Finder execution must show GFM structure from the real packaged
worker for normal and symlink selection before this slice merges.

This slice does not render math, Mermaid, D2 or Graphviz, supply linked local
resources, prove visual theme parity, or satisfy final signed clean-install
acceptance. Those stay in issue #7.
