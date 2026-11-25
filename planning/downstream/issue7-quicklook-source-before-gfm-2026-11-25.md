# Publish Quick Look source before Markdown parsing

## Owner summary

Quick Look already kept a complete reply when a later diagram stalled. The
worker still rendered the entire Markdown document before marking its first
fallback as ready. If that initial render took longer than the worker's fixed
deadline, Finder received no MostlyText reply. The worker now marks an escaped,
passive source view first. It publishes the familiar formatted Markdown as its
first derived snapshot when parsing succeeds, followed by math and diagrams.
The three-second child deadline, four-second extension bound and byte ceilings
are unchanged.

## Source and ordering

Baseline main is `f2220e9da55b1fd7d99348d225a9f22ee6873f73`. Before this
change, `sourceWorkerMain` called `QuickLookSourceFallback.replyHTML` to run
GitHub Flavored Markdown rendering before writing descriptor 4 and its `F`
completion marker. The parent can return only a marked complete descriptor.
Thus a stalled initial parse could not return the authored source even though
the parent killed and reaped the child on schedule.

`sourceOnlyReplyHTML` escapes the decoded selected source into the existing
passive document shell without invoking the Markdown parser. The worker writes
it and the marker before starting any formatting or technical work. The
derived stage then publishes ordinary formatted Markdown, including for files
without math or diagrams. Later complete snapshots still alternate between the
two derived descriptors; the parent selects the last marked complete one and
never selects a partially written candidate. Source decoding and file identity
checks remain before publication and are unchanged.

## Verification and limits

The focused source test checks the escaped shell, inert authored link/script,
maximum-size quote expansion under the existing reply cap, and the separate
formatted Markdown result. Existing process fixtures exercise a completed
fallback followed by blocked/partial derived work. The locked Release product
build and installed Finder checks must still confirm ordinary GFM, math,
Graphviz, Mermaid and source fallback at this exact head. The change establishes
an earlier fallback publication boundary; it does not prove a specific
historical Finder blank, a physical display deadline, full renderer limits,
D2 static output or the final signed candidate.
