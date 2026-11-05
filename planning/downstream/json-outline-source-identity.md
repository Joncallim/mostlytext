# Keep JSON outline paths and source coordinates unambiguous

Different JSON nodes need different outline identities, and a changed source
needs fresh ranges even if its Unicode looks the same. Raw dotted key paths
collide with punctuation-bearing keys and Swift String canonical equality;
the controller also skips rebuilds after canonically equivalent byte changes.
Fix those two pure model boundaries without changing authored JSON or the UI.

## Baseline and scope

Stable source is PR74 `4b190bebe8b3b120305ad6b6a4e2521dec5ca33d`; main is
`a95ff1fc4498e925eb1582fa6eb9e7fab5baf5ad`. Require PR72/73/74 qualification
and integration before merging this dependent unit. #17 owns the scoped audit
findings and #8 retains final native/review acceptance. JSONParser already uses
exact UTF-16 keys and permits distinct NFC/NFD names; outline IDs must not merge
them. Existing JSONOutlineIdentity/JSONOutlineChannel tests require ordinary
paths and collapse/selection remapping across formatting to remain stable.

Only JSONOutlineBuilder path construction, OutlineController's source no-op
comparison and focused tests/evidence change. Keep public String IDs, titles,
array indices, parsing, formatting, source ranges, lifecycle and app/UI unchanged.
The inspected JSON collapse/selection state is explicitly in-memory only, with
no serialization/migration consumer. No document state is rewritten.

## Stable path encoding

Keep `.key` segments for nonempty ASCII letters/digits/underscore/hyphen keys.
All other object keys use a quoted bracket segment containing base64 of their
exact decoded UTF-8 bytes. Numeric array segments remain `[index]`. The resulting
IDs are ASCII, object/array segments cannot alias, and punctuation cannot inject
an extra path segment. Literal titles stay readable; the encoding is an internal
identity, not a user-facing label. No index-based disambiguation that changes
when objects reorder. Escaped and literal spellings of the same decoded key
keep one identity. Preserve existing simple-key IDs and tests unchanged.

The JSON controller compares optional last/current source via exact UTF-8 views:
nil/nil matches, nil/some differs, some/some matches only exact bytes. Existing
availability change detection and exact-source no-op behavior remain intact.
No new dependency or full-document Data allocation for the rebuild comparison.

## Verification

First run the same source-identical owned non-GUI JSONSupport/OutlineUI/parser
fixture on old source with new golden tests. Prove punctuation-vs-nesting,
array-vs-key and canonical-Unicode ID collisions, precise per-ID lookup/collapse,
stability across formatting/reordering, and NFC/NFD source rebuild/ranges.
Use original modules (Foundation/Observation/JSONSupport/MarkdownEngine only),
exact pinned parser dependencies and existing suites; no AppKit/WebKit/SwiftUI
or product execution. Preserve failures and source/log hashes. Then run the
same new tests and existing related suites in Debug and Release, pinned format,
strict lint, Compliance/inventory and full hosted locked package/app/CLI CI.

Review/merge exact qualified source in dependency order, verify actual merged
tree/parents/clean main, update #17 evidence and immediately reassess all open
issues. Native sidebar/keyboard acceptance and all broader release gates remain.
Stop on stored-state dependencies, changed simple-key IDs, non-injective encoding,
changed source ranges or a need to weaken existing tests/performance budgets.
