# Issue #18: mounted viewport Markdown owner

## Owner summary

Large Markdown files currently lose syntax colour above 8,192 UTF-16 units so
ordinary typing remains responsive. This slice will give each mounted editor a
bounded, viewport-only colour owner. The current reduced mode remains the
product default until the complete Release typing and painting path passes the
1 MiB budget. Unsupported edits will show plain text while a fresh parse runs;
old colour must never be presented as current content.

## Baseline and reconciliation

The implementation starts from `main` `ae61d45b` plus the #18 owner/cache PR
head `70d217d7`. The latter is a dependency, not merged evidence yet.
`NeonSyntaxHighlighter` currently owns theme chrome, Neon's full highlighter,
the storage gate and 8,192-unit fallback. `MarkdownSectionCache` can answer
clipped root/injection tokens from immutable section snapshots and update one
bounded word paragraph. `EditorTextSystem.visibleUTF16Range` returns mounted
TextKit 2 paragraph bounds or nil. `MarkdownParseAuthority` exists but is not
attached to the highlighter. A test-only public-styler probe proves that
`TextSystemStyler<TextViewSystemInterface>` can paint and shift clipped tokens;
it does not prove production event ownership or latency.

The original #18 request is a complete 1 MiB/50 ms keypress budget, including
paint and parser work. Cache-only milliseconds and CI compilation do not meet
that request. The current size fallback stays authoritative until a measured
Release app and appropriate native acceptance justify activation. The existing
status note explicitly says syntax highlighting is **off** for large files.
Activating viewport colour therefore also requires a distinct effective mode
and localised note that describe visible-only highlighting truthfully.

## User journey and invariants

Open a large Markdown document, scroll to a heading or inline syntax, type
inside a plain word, scroll away and back, then change theme or source. The
visible colour must match a fresh parse of the current source after each
settled operation. The authored source, undo, selection, marked text, saved
bytes and export must remain unchanged by presentation work.

- Only one owner is attached to one `EditorTextSystem` lifetime. A ticket from
  any prior edit, language, presentation or lifetime cannot publish.
- The actual storage delegate invalidates authority synchronously, before
  `EditorView.Coordinator.textDidChange` updates its model revision.
- The pre-edit callback may copy only its selected bounded old window. It may
  never retain `NSTextStorage.mutableString` across callbacks.
- An edit without exact pre/post geometry and replacement-byte agreement takes
  the deferred full-parse path. This includes undo, IME, programmatic reload,
  nested assists and structural/word-edge edits.
- No parsing, token query or rendering-attribute work runs inside
  `NSTextStorage.processEditing`. Its callback only invalidates, pairs and
  schedules work. The editor's text and storage remain the sole authorities.
- A nil, empty, oversized or stale mounted viewport cannot authorize paint.
  A viewport request is capped at 65,536 UTF-16 units.
- No document content leaves the process and no new filesystem or network
  capability is introduced.

## Ownership and data flow

`Highlighting` owns a main-actor `MarkdownViewportOwner` retained by
`NeonSyntaxHighlighter` only for eligible Markdown. Initially its production
activation is held behind the existing fallback, rather than showing colour
while the UI says it is off. It owns a
`MarkdownParseAuthority`, `MarkdownEditPairing<MarkdownSectionCache.Window>`,
optional cache, pending parse task, and public Neon styler. The editor owns
TextKit, its storage and scroll view. The existing `HighlightingStorageGate`
remains the sole storage delegate. The owner registers its pre-edit callback
and the gate's geometry callback for its lifetime, and removes both on
teardown. No second storage delegate is installed.

1. On mount or an unsupported edit, copy an immutable source snapshot once,
   create a ticket, and parse on a detached executor. The task returns an
   immutable `LanguageLayerTreeSnapshot`, not a live parser. Debounce rapid
   unsupported edits so only the latest snapshot needs work.
2. On completion, compare ticket, requested language, live storage length and
   source identity before installing `MarkdownSectionCache`. A stale result is
   dropped without changing presentation.
3. On a pre-edit proposal, select one bounded old window for the current
   mounted viewport and retain its owned content/geometry. The storage gate
   invalidates the current ticket at the actual mutation and compares the
   proposal to actual post-edit geometry. If it matches, copy the bounded new
   window and defer the local parse/cache replacement until after the gate
   returns. If it fails, clear visible paint and schedule a fresh full parse.
4. The public styler's synchronous provider returns only cache tokens clipped
   to the current mounted viewport and request range. A missing cache returns
   a replacement with no tokens for that range. It never scans live source.
   The styler receives `didChangeContent` for every actual edit, including
   edits that cannot use the local cache.
5. Clip-view bounds changes invalidate and validate the newly visible range.
   Theme/font changes invalidate the owner and repaint the current viewport.
   Language changes and teardown remove observers, cancel pending work and
   refuse all old tickets. No highlight work can resurrect a discarded owner.

## Failure, performance and evidence gates

Test a real mounted editor with controlled held parses across a word edit,
structural edit, reload, theme change, language switch and teardown. Include
surrogate pairs, CRLF, word edges, IME, undo/redo and viewport moves. Compare
rendered attributed runs to independent fresh full-parse captures, including
stale-result refusal. Verify no source, selection or undo side effects.

Measure on an optimized 1 MiB Release app: storage callback, bounded window
copy/parse, main-actor edit duration, background queue, peak memory and
keypress-to-settled-colour. The #18 50 ms budget is for the complete user
keypress path; `MarkdownSectionCache` microbenchmarks alone do not qualify.
Run package, app, UI compilation, editor/theme and controlled-highlighting
qualifications on the exact PR head. The original 8,192-unit fallback remains
until these proofs and separate-account native acceptance pass.

Activation adds a truthful visible-only state and status explanation, with
English and reviewed non-English catalog entries before final E16 freeze. No
export format changes. Existing source-preservation checks still run.

## Foundation checkpoint and remaining activation work

The local foundation now has a per-editor parser session and a public-styler
viewport painter, with mounted rendering tests. It is not attached to the
shipped `NeonSyntaxHighlighter`; the 8,192-unit reduced fallback and its status
copy still describe actual product behavior.

TextKit can report a widened paragraph range for one proposed character edit.
The exact-range adapter rejected every such mounted edit. The session now
copies its selected old window (at most 65,536 UTF-16 units), and pairing
admits a widened report only when that report is contained in the window and
the whole post-edit window equals one application of the proposed replacement.
Nested or unobserved edits, a changed neighbor, and an edited range outside
the window still fail closed. Interior plain-word insertions and deletions use
the same proof; structural changes take a fresh full parse.

The cache now partitions a nested heading tree into disjoint parent-prefix,
child and grandchild entries. A local parse changes only the edited entry and
shifts later ranges; a fresh full-parse oracle matches captures after edits at
all three levels. This removes the specific 1 MiB root-section rejection
without changing the 65,536-unit window cap.

An opt-in mounted Release probe generated 1,048,804 UTF-8 bytes with a `#`
parent above many `##` sections. Twelve alternating insertions and deletions
entered the local path (12 selected, 12 matched, 12 local parses, one full
parse at open). In that controlled run, synchronous edit calls were 9–36 ms
and current viewport color settled in 11–38 ms. The earlier unpartitioned
variant took full parses and settled around 700 ms. These are source-level
measurements on one local machine, not a whole-app, multi-workload, p95 or
native acceptance pass.

Before default activation, measure the Release app on the complete 1 MiB
workload matrix, including large leaf sections, dense inline markup and
structural edits. Wire the owner into the highlighter with an honest
visible-only mode, theme/font and lifetime handling, and a reviewed localized
status note. Separate-account native acceptance remains a final gate for the
exact app build.

## Opt-in integration checkpoint

The follow-on integration attaches the parser session and viewport painter to
`NeonSyntaxHighlighter` only when its new `enableViewport` argument is true.
The app's `SyntaxHighlightStore` does not enable it, so the shipped large-file
behavior remains the reduced fallback. This avoids presenting a source-level
probe as a qualified product feature.

With the opt-in path, one mounted oversized Markdown editor owns one session,
one painter, the existing storage gate, and no full-document Neon highlighter.
The `visibleOnly` state and status note describe the limited colour accurately.
Language switches, close and the full-mode size crossing detach the old owner;
an asynchronous crossing callback cannot recreate it after teardown. Explicit
rehighlight invalidates an older parse ticket before starting a new snapshot.
The painter declines to touch marked composition and removes its last bounded
paint if mounted viewport geometry becomes unavailable.

The local Release mounted integration tests cover edit, theme, font, explicit
rehighlight, language switch, close and a deferred threshold crossing. The
unsigned app and CLI compile with locked package versions; compiled-string
coverage confirms every extracted key has a catalog route. The two new status
keys have English copy and review placeholders in French, Japanese and Polish.
An additional opt-in 1,048,804-byte Release probe uses the actual highlighter
integration for 12 alternating plain-word edits. Both local runs selected and
matched all 12 bounded windows, did 12 local parses and one full parse at open.
The first run's synchronous calls were 12–53 ms and settled colour 14–58 ms;
the repeat was 8–39 ms and 11–41 ms. The first run crosses the 50 ms target,
so this narrow probe is not a budget pass, even though its repeat is faster.
These source and build checks do not satisfy the complete 1 MiB keypress matrix,
native accessibility and IME acceptance, non-English review, signing or exact
release-candidate acceptance. The default flag remains off until those gates
are met and recorded on issue #18.

## Requested-range paint work

The public styler can validate a subrange of the visible viewport. The initial
opt-in adapter queried every token in the full viewport for each such request,
then relied on the styler to clip the result. The session now intersects a
requested range with the mounted bounded viewport *before* asking the cache for
captures. The same clipped range is handed to the styler, so paint authority
and token selection agree. A request outside the viewport or with an invalid
location returns no tokens. The existing full-viewport query remains for
readback and diagnostics. This is a bounded work reduction, not a change to
Markdown semantics, default activation, or the 50 ms acceptance threshold.

On the same opt-in 1,048,804-byte word-edit fixture, two Release runs after this
range change each selected and matched all 12 windows, used 12 local parses
and one full parse at open, and restored the exact original source. The first
measured synchronous calls at 8–36 ms and settled colour at 10–38 ms; the
second at 9–41 ms and 11–43 ms. The earlier full-viewport variant's first
run had one 53 ms call and 58 ms settlement, but these unmatched local runs do
not prove the range change alone caused the difference. Neither run covers
structural edits, dense inline or long leaf sections; the complete production
50 ms budget and native gate remain open.

## Long leaf paragraph partition

A section with many ordinary paragraphs can still exceed the window cap even
without nested headings. The cache now splits direct paragraphs in oversized
sections into disjoint entries, retaining the parent snapshot for heading and
gap ranges. Short leaf sections retain one entry.
Local plain-word edits can therefore reparse a small paragraph inside a long
leaf. A regression with a greater-than-1-MiB single section, 4,000 repeated
paragraphs and two edited target paragraphs compares bounded cached captures
with fresh full parses after both edits. An individual paragraph over 65,536
UTF-16 units still falls back to a full parse. This is a source-level correctness result; the
complete 1 MiB workload timing and product activation gates remain open.

Three opt-in 1,048,804-byte Release highlighter runs after this change still
selected and matched all 12 edits, did 12 local parses and one full parse at
open. Their worst synchronous edit calls were 62, 60 and 56 ms, with
corresponding paint settlement at 65, 62 and 58 ms. The runs were unmatched and
cannot attribute those outliers to this partition change, but they do fail to
establish the 50 ms threshold. Keep the default owner disabled.

## Retire scrolled-off colour

The first opt-in painter retained syntax attributes from an earlier viewport
after scrolling away. A mounted AppKit regression first failed when it painted
the opening paragraph, scrolled to the tail and found red syntax attributes
still attached at the opening range. The painter now removes only the portions
of the last painted range outside the new viewport before painting it, avoiding
a growing trail of stale attributes. It also clears the last range when mounted
geometry disappears. The same regression passes in both scroll directions,
compares each visible range with a fresh full parse and preserves source text.
This is bounded source-level behaviour; native scrolling and the full budget
matrix still require acceptance.

## Bound physical parser work

Cancelling the outer viewport session task does not interrupt a synchronous
tree-sitter C parse already running in a detached task. Previously, rapid edits
could start another physical parse for each new ticket. A shared two-slot parse
owner now admits at most two active Markdown snapshots across mounted editors;
cancelled queued requests leave promptly, while a cancelled active request
retains its slot until its physical parser returns. The session still checks
its generation before publishing, so the queue does not relax stale-result
guards. A controlled test holds two injected parser operations, cancels a
queued third, cancels one active owner and proves the replacement starts only
after that operation is released. The production owner remains opt-in pending
complete workload, timing and native acceptance.

The opt-in 1,048,804-byte Release highlighter run with this queue selected and
matched all 12 word edits, used 12 local parses and one full parse at open, and
restored exact source. Its worst edit call took 64 ms and colour settled in
67 ms. The queue bounds physical overlap; this probe does not pass the 50 ms
keypress budget or establish whole-workload performance.

An opt-in paired Release probe now runs the same mounted 1,048,804-byte word
edits through the shipped reduced fallback and the proposed viewport owner in
separate text systems. In three local runs the reduced fallback's worst edit
calls were 61, 62 and 37 ms; viewport's were 37, 37 and 54 ms. The viewport
path selected/matched 12 of 12 bounded windows in each run and restored exact
source. The first probe run exposed an assertion-macro test error after both
measurements; the assertion was corrected and the subsequent runs passed.
These small, ordered runs cannot establish comparative p95, causality, whole-app
responsiveness or the 50 ms release budget. They do show that a greater-than-50
ms edit call is possible even without viewport parsing on this fixture.
