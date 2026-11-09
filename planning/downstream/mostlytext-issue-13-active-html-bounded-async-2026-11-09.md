# Issue #13: bounded background reads for active HTML resources

## Owner summary

The saved HTML preview keeps its current automatic access to files beside the
document. Its nearby images, styles, fonts and media are now read on bounded
workers, so a slow local file read does not hold up the app's main thread.
Stopping a request, saving a newer revision or closing the preview immediately
removes the old request's permission to send WebKit callbacks. A read already
underway retains its pinned directory only until the worker finishes.

This introduces a user-visible size policy. An individual local resource over
16 MiB fails to load in the preview. The shared admission service permits at
most 64 MiB cumulative delivered resource input and 512 requests per saved
load, 128 MiB reserved/retained input across loads, four workers globally and
two workers per load; queues are limited to 128 globally and 32 per load.
HTML subresources also use the existing 128 MiB per-load / 256 MiB global copy
budget and an 8 MiB encoded-output ceiling during CSP hardening, so HTML can
fail below the raw 16 MiB limit. The main saved HTML source retains
its existing behavior; this slice does not change its size or hardening path.

## Baseline and ownership

This slice stacks on the active resource-containment change at PR #190 head
`6ccd215b69eea7e11d6245f65cfacc411a9980e9`, which pins the saved
document's directory and reads through `ContainedResourceReader`. It reuses
`PreviewResourceAdmission` for worker, queue, byte and cancellation accounting.
The active `HTMLPreviewView` still debounces clean saved generations and keeps
the last rendered page during dirty edits. The separate explicit-grant
`SecuredHTMLPreviewView` remains inactive.

`PreviewDirectoryGrantBacking.acquireAutomatic` takes the real saved document
URL, starts access to its parent, and pins that directory before WebKit loads.
It does not create a panel receipt or extend access beyond the document's
directory. The handler accepts that authority only when the request's base URL
is the document URL's parent. A missing or unavailable directory still allows
the main saved HTML to render, while its subresources fail closed. Existing
in-directory symlinks continue to work; escaping and swapped paths remain
subject to the descriptor reader's containment checks.

## Verification and remaining acceptance

Source controls cover automatic authority revocation and draining, an active
16 MiB boundary, HTML hardening and copy-budget denial, non-UTF-8 HTML with a
CSP header, blocked-worker supersession and stop, and the earlier
path/symlink/callback cases adapted for asynchronous delivery. These app
tests instantiate WebKit and must run in a hosted or test-account environment;
compiling them on the owner desktop is not an execution receipt. The current
test desktop's native preview corpus, Release memory/latency calibration and
final RC acceptance remain open. This change does not claim a user-visible
folder-grant prompt or expand the preview to a different directory. Save As and
rename advance `FileDocument.mutationGeneration`, so they schedule a new saved
HTML load with the new URL. A lower-generation switch to a distinct document
through a reused `HTMLPreviewView.Coordinator` has not been proven or ruled out
and remains an issue #13 lifecycle review item outside this read-budget slice.
