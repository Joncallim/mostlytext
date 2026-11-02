# Issue #53 — Compatible settings and deliberate legacy import

## 2 November 2026: production optional editor import

The [production import architecture](production-editor-import.md) supersedes the older pending activation/font/theme statements below. The application now runs the optional consent/journal recovery step before constructing mutable settings/theme/session/document owners. Exact representable installed fonts and the three reviewed Boolean mappings are eligible for explicit per-field selection; legacy style names have no exact aliases and never alter current theme storage. App/UI-test hosts bypass real-domain import. Whole-install identity migration, native/private-candidate evidence, final localization, signing and public release remain separate gates.


## 1 November 2026: conditional persistent-domain publication

The [conditional writer architecture](conditional-settings-publication.md)
adds an explicitly named persistent-domain store alongside the existing generic
injectable store. Ordinary edits and the optional migration primitive share the
same synchronous MainActor owner and saved-value admission. Registered/global
fallback values do not count as persisted presence or preserved backups in this
bound store. Domain validation rejects the original MacDown/system domains
before opening a suite; no production caller is switched to it yet.

The publisher compares exact before/desired revisions, requires a matching fresh
source before a first write, preserves conflicting later values and verifies
exact persistent-domain readback. Repeating an already-desired write is a no-op;
failed readback never claims completion or rolls back a third value. All 115
AppSettings tests pass in Debug and Release, including 13 new synthetic-suite
controls. The initial combined run exposed a process-wide registration fixture
leak; fixtures now restore their prior volatile registration domain. Full hosted
CI and merge evidence belong in the PR record.

This supplies the single-domain write boundary, not the durable E17 journal,
bootstrap/consent UI, font/theme conversion or real isolated-account rehearsal.
Readback is not proof of defaults-daemon disk durability or multi-key atomicity.
#53 remains open for those requirements.

## 1 November 2026: exhaustive report and consent-bound write preparation

Baseline: integration `1b79485699199509ec15e0baa34906e5ffd4b63e`; master
`15c0fae22f7618e94c82681227057c66011be2a9`. The executable data-only report
now covers all 52 stored, four calculated and two transient declarations. The
source-backed JSON record and a Compliance test bind every key, value kind and
report policy to the Swift catalog. Unknown keys, exact legacy misspellings,
Boolean/numeric distinctions, invalid enums and malformed fonts have explicit
outcomes. No report entry reads a URL, unarchives data or applies a preference.

The three reviewed editor Boolean conversions now produce deterministic desired
editor bytes after exact source/destination revalidation. Selection is explicit;
replacing any persisted field requires separate consent for that field, including
when the existing value equals the default. Every unselected editor value is
retained. Unsupported/future/non-Data destinations are blocked. A proposal binds
mapping version, source digest, before/desired raw revisions and selected fields.
Replay distinguishes captured-before, already-desired and a conflicting third
value; the last is preserved. These are pure writer inputs and replay decisions,
not an executed or atomic preference transaction.

Source reconciliation found two earlier candidate equivalents were not exact:

- In upstream `MPDocument.m:774–781` at pinned `3e2a2bf`, disabling
  `editorInsertPrefixInBlock` stops list/quote continuation but still calls
  `completeNextIndentedLine`. Current `continuesMarkdownPrefixes` also gates
  indentation. The legacy value is reported unsupported rather than silently
  changing its meaning.
- The old matching-character switch also controls the original character map and
  strikethrough selection wrapping (`NSTextView+Autocomplete.m:99–122,208–233`).
  Current structural/Markdown pairing does not reproduce that whole policy.
  It is reported unsupported; no partial conversion is advertised as exact.

The font row validates the exact legacy `name`/`size` shape and produces an
unresolved PostScript-name request. E17 must resolve the installed font and prove
that the current family-based destination reproduces it before offering an
applicable change; missing or nonrepresentable faces remain unsupported. Theme
aliases, renderer/update-policy rows, actual consent UI, shared serialized writer,
transaction journal and isolated native/live-apply migration remain outstanding.
The frozen plan never grants file authority or replays IPC. #53 remains open.

A local Foundation-only harness uses copied unmodified AppSettings/JSONSupport
sources and six pure test files, without an application host or a real preferences
domain. Its first setup lacked JSONSupport's resource declaration; after fixing
that harness, compilation found a missing static qualifier in the shared mapping.
Both failed logs are retained. Final focused and full hosted results belong in
the PR verification record; this section does not infer native acceptance.


## 2026-10-25 local admission slice

The next pure `LegacyImportPlan` step classifies only the three verified editor
Boolean suggestions. A missing destination domain or a field whose absence was
proved by a future protected decoder may be proposed as a default fill. Every
valid persisted value wins, including a value equal to the current default;
unreadable, future-version and unknown-presence destinations block automatic
fills. The plan carries source and destination revision identities for a later
write-boundary recheck. Its classifier consumes explicitly supplied states;
it does **not** parse or write a persisted destination blob and cannot itself
prove that a field is absent. Thirteen focused plan/conversion/snapshot tests
pass with locked dependencies; strict lint and format checks pass. This is
not consent, a serialized writer, journaling, recovery or a migration run.

The next isolated, read-only fixture slice classifies three direct editor Boolean
keys: `editorAutoIncrementNumberedLists`, `editorConvertTabs`, and
`editorSmartHome`. `LegacyEditorBooleanConversion` preserves explicit true and
false, distinguishes absent keys from false, and reports present non-Boolean
values instead of coercing numeric or string lookalikes. It produces proposals
only; it does not persist them or infer that a default-valued destination is
absent. The three conversion fixtures and 44 adjacent snapshot/editor-behavior
tests pass on the locked package build; strict lint and format checks pass. The
font, prefix-continuation, and matching-character candidates remain
unmapped pending their respective value or behavioral fixtures. Destination
precedence, consent, E17 journaling, E23 theme IDs, and real-domain rehearsal
remain outside this slice.

An isolated local #53 branch based on release-debt candidate `e2434fab` now has a pure
`LegacyPreferenceSnapshot(domain:)` value. It copies an explicitly supplied domain,
preserves property-list value kinds (including Boolean versus number), rejects unsupported
objects and non-finite numbers, and bounds depth, entries, strings, aggregate admitted bytes and the
canonical encoded form. Its sorted typed digest can identify a frozen source snapshot for
a later plan. It does not access the original MacDown preferences, apply a setting, grant
file access, or implement consent, journaling or import. This is preparation for the
existing immutable-plan contract below, not evidence that #53 can close.

Four synthetic-domain snapshot tests pass with locked Swift packages. Real-domain
disposition, precedence, settings migration, the E23 theme destination and the
E17 isolated-account rehearsal remain separate acceptance gates.

## Owner summary

Import useful original-MacDown preferences without changing that app, reviving inert parser toggles or overwriting the new editor's deliberate choices. First preserve development/beta settings across schema changes; then perform the separate opt-in original-MacDown import. Every legacy key receives an explicit disposition.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Read [README](README.md) and [readiness review](READINESS_REVIEW.md). E22 exclusively owns the inert MarkdownParseOptions cleanup. This document changes no active E22 code and cannot close its parser half. The full issue closes only after both halves have evidence.

## 2026-10-18 current-source reconciliation

Reviewed integration baseline: `d3cc8883a08df02a9a98165b1833ca950948dc5d`;
live master: `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. The live issue's
30 September ownership clarification remains binding: #53 owns semantics and
tests; #18 executes the agreed map after destination settings/themes freeze.

The missing-status-bar historical decode is already implemented and tested.
A narrower regression was reproduced: a present JSON `null` was treated as an
absent field. The bounded correction rejects that malformed value while keeping
the absent-field default and both Boolean values. Test preference suites are
explicitly isolated and remove only their own persisted domains.

The [machine-readable disposition record](legacy-preference-dispositions.json)
covers all 52 stored, four calculated and two transient properties in the pinned
legacy header/implementation. Its read-only checker verifies source digests,
declaration coverage, exact spellings and current destination candidates. It is
**not** an importer, a complete conversion map or proof of migration readiness.
Six destination candidates still need semantic and precedence fixtures; E23
theme and other owned policies remain unresolved.

The store's existing first-unreadable-blob backup is narrower than the protected
writer required below. An isolated baseline probe demonstrates that an ordinary
save replaces a future-version primary blob while retaining its first backup;
a second unreadable generation is not retained after another save. Non-Data
objects are neither reported as unreadable nor retained on replacement. This
contradicts a claim of complete no-clobber compatibility, and is an explicit
stop boundary for this slice: remedying it requires the shared admission,
error-reporting and recovery policy specified below, not another decode default.
See [reproduction and evidence](evidence/settings-53-2026-10-18/README.md).

## 2026-10-25 integration disposition checkpoint

The clean `integration-final` baseline
`02ef38df8185c5f411dfc57f074ef5a7bea29384` was reconciled with the live
issue, E17 gate, AppSettings, Themes and `MarkdownParseOptions`. The resulting
[source-backed disposition and migration test contract](evidence/settings-53-2026-10-25/MIGRATION_CONTRACT.md)
uses the existing machine-readable declaration record as its exhaustive map.
It makes the current boundary explicit: six editor-field destinations are
candidate equivalents needing final-schema and semantic/precedence evidence;
theme aliases and owner-policy destinations still need their E23/E17 freezes;
and no importer, preference access or writer was activated. The five formerly
inert parser fields are no longer modelled as switches: tables, task lists and
strikethrough are unconditional, while extended autolinks and footnotes are
unsupported. `blockDirectives` remains the only real opt-in parser preference.

## Historical 2026-10-14 reconciliation

The current source still matches the boundary above: `LegacyPreferencesDetector`
only performs presence detection for `com.uranusjr.macdown`, while
`UserDefaultsAppSettingsStore` owns five whole-JSON domains
(`appSettings.general`, `editor`, `markdown`, `previewExport`, and `formats`).
The store preserves unreadable raw bytes and reports them; it does not import
legacy values. No real user domain was read or changed during this
reconciliation.

The key-by-key table below remains the source-grounded disposition map, not an
implemented migration. Parser-specific rows remain delegated to E22, and
theme rows remain delegated to E23. The next executable unit is still
SETTINGS-COMPAT plus a machine-readable coverage test; no legacy import,
preference write, or migration completion claim is made by this integration
branch.

## Historical source finding — missing-field decoder now implemented

LegacyPreferencesDetector still only checks `com.uranusjr.macdown`. Current settings are whole JSON blobs under appSettings.general/editor/markdown/previewExport/formats. Original MPPreferences.h/.m at upstream `3e2a2bf101c215c143bf00d9f857965f0ee82487` define the legacy keys below. Do not instantiate MPPreferences: its initializer writes defaults/version state and cleans old autosave records.

The older `EditorSettings` added required `showsStatusBar` with an initializer
default but synthesized decoding. That could reject a pre-E22 blob and return
the whole default domain. Current explicit decoding addresses this historical
finding; it must not be reimplemented as if still absent. The broader
protected-write contract remains required as described above.

## Settings compatibility — first executable unit

The first import-planning slice now has a pure editor-domain admission candidate.
`LegacyEditorDestinationEvidence.decode(_:)` accepts caller-supplied raw bytes,
classifies absence, historical/current valid data, malformed data and unknown
future data, retains the decoded `EditorSettings` only for admitted bytes, and
binds its decision to the exact byte digest. It does not read
preferences or write settings. `LegacyImportPlan` accepts only this decoder's
evidence, so a caller cannot invent field absence from a default-valued model.
For an existing non-Data value, the eventual storage adapter must report an
unreadable domain rather than call `decode(nil)`; nil means proven absence.

This candidate adds the local, Foundation-only `AppSettings` → `JSONSupport`
dependency. Its purpose is duplicate-key admission before Foundation decoding;
Foundation's JSON deserializer can silently collapse duplicate keys. The
dependency is acyclic and carries no renderer, document or network capability.
The ordinary `UserDefaultsAppSettingsStore` editor load and write-protection
check now use this same admission result. A read-only `editorStoredDomain`
snapshot exposes the decoded evidence to a future importer; it distinguishes
an absent key from a present non-Data value before any Data cast. Unsupported
bytes remain at the primary key and startup exposes only a session-safe
default. This does not migrate or rewrite stored data. The serialized writer,
consent flow and execution journal remain separate review gates. Passing
these compatibility tests is not migration completion.

AppSettings owns a typed versioned decode/migration adapter, used by normal startup AND the importer. Do not implement a one-off importer decoder while ordinary startup still falls back destructively. Inspect raw persisted data before constructing mutable models or writing defaults. Distinguish absent, known-compatible older schema, valid current, malformed and unknown future data.

For a known older editor blob missing showsStatusBar, preserve every present valid field and supply true ONLY for the missing new field. A present false remains false. Apply the same additive-field discipline to every final E22/E23 setting. Validate ranges explicitly during decode; constructor clamping is not automatically invoked by synthesized Decodable. Known removed parser keys receive the final E22 disposition, not a fake stored control.

Use explicit migration steps and stable schema/provenance records. Do not add a required schemaVersion key that itself makes all old blobs unreadable. Treat existing schema-less objects as a named historical schema with an exact fixture. Unknown/future or malformed raw blobs are retained and reported; a temporary safe UI fallback does not authorize replacing them with default JSON. Persist a migrated domain only after validated staging and before/desired digest checks through the serialized settings writer. Read-back success is required; user defaults are not a multi-key filesystem transaction.

Regression fixture SETTINGS-COMPAT: pre-E22 valid editor JSON with nondefault font, indentation and disabled assists; same with a present false showsStatusBar; missing optional additive fields; missing old mandatory fields; invalid types/out-of-range values; unknown future version; and corrupt bytes. Assert exact preservation of valid existing values, explicit single-field defaults, original-byte retention on unsupported input and idempotent repeated launch/import. No legacy MacDown account/domain is needed to run this unit.

## Models, admission and ownership

AppSettings owns LegacyPreferenceSnapshot, LegacyImportPlan, LegacyKeyDisposition and pure conversions. E17 owns bootstrap/consent/journal coordination; E23 owns safe theme catalog insertion. A plan freezes source hash, destination raw hashes/schema generations, proposed per-field changes, warnings and dispositions. Separate mapped from applied. Every input key is mapped, equivalent-unconditional, unsupported, obsolete, transient, invalid or unknown.

Initial bounded admission: property-list primitives, 1 MiB source snapshot, 2,048 keys, ordinary strings at most 4 KiB and finite validated numbers. Distinguish CFBoolean from arbitrary numeric/string coercion. Never unarchive arbitrary objects, execute CSS/templates/scripts, replay IPC or turn a stored URL into a filesystem permission. Unknown keys appear in the local report, not the destination settings.

## Complete declared legacy-key disposition

Preserve exact legacy spellings. This table is exhaustive for the stored keys declared in the inspected header; calculated/transient properties are handled below. At final E22/E23 baseline, bind only real exact-equivalent settings to destination symbols and produce a machine-readable map. This is interface rebinding, not permission to add absent product features. A coverage test rejects an unclassified known key.

| Stored legacy key | Disposition / conversion |
| --- | --- |
| firstVersionInstalled | Original-app provenance only; never the new app's first-run/migration state. |
| latestVersionInstalled | Same; not proof the new product completed initialization. |
| updateIncludesPreReleases | Explicit update-channel suggestion only; no hidden channel/feed/key import. |
| supressesUntitledDocumentOnLaunch | No baseline equivalent. Untitled suppression is not session restoration; retain misspelling and report unsupported unless final exact behavior exists. |
| createFileForLinkTarget | Unsupported unless the exact final action policy exists; never enable implicit file creation from import. |
| extensionIntraEmphasis | Parser-specific grammar difference; no generic Markdown switch. |
| extensionTables | Current E22 parser always supports tables. True requests an unconditional capability; false has no disable preference. Never import an inert Boolean. |
| extensionFencedCode | Core grammar: true means equivalent unconditional capability; unsupported request to disable on false. |
| extensionAutolink | Current parser supports CommonMark angle-bracket autolinks, not GFM extended bare autolinks. Legacy semantics are not interchangeable and no toggle exists. |
| extensionStrikethough | Preserve misspelling. Current E22 parser always supports strikethrough; false has no disable preference. |
| extensionUnderline | Unsupported grammar; not editor underline formatting. |
| extensionSuperscript | Unsupported unless the actual final grammar supports it. |
| extensionHighlight | Unsupported grammar; not syntax highlighting. |
| extensionFootnotes | Current engine does not support footnotes; the inert option was removed. Preserve the unsupported request in any future import report. |
| extensionQuote | Original extension differs from ordinary block quotes; unsupported unless exact equivalent exists. |
| extensionSmartyPants | Unsupported typography; no punctuation normalization or hidden system substitution changes. |
| markdownManualRender | Manual render is not hiding Preview; unsupported at baseline. |
| editorBaseFontInfo | Validate name/size; resolve installed PostScript name through NSFont to the final FontDescriptor on MainActor. Preserve current font and warn if unavailable; never download. |
| editorAutoIncrementNumberedLists | Boolean -> editor.autoIncrementOrderedLists. |
| editorConvertTabs | Boolean -> editor.convertsTabsToSpaces; does not encode indentation width. |
| editorInsertPrefixInBlock | Unsupported: legacy false retains indentation continuation, while the current prefix setting also disables it. |
| editorCompleteMatchingCharacters | Unsupported: the legacy character map/strikethrough wrapping is not the complete current pairing policy. |
| editorSyncScrolling | Only an exact final scroll-sync preference; not preview layout or an invented switch. |
| editorSmartHome | Boolean -> editor.smartHome. |
| editorStyleName | Only curated exact compatible theme aliases; no nearest-name guess or executable old-style import. Unknown/custom style remains unsupported with safe explicit conversion outside this import. |
| editorHorizontalInset | Only same-unit final layout preference; not page width. |
| editorVerticalInset | Only same-unit equivalent; not line spacing. |
| editorLineSpacing | Verify points versus multiplier before any real mapping; no newline/font-size rewrite. |
| editorWidthLimited | Map together with maximum width only if exact final width policy exists; unsupported otherwise. |
| editorMaximumWidth | Valid finite positive points plus enable flag; saved number alone cannot enable a width restriction. |
| editorOnRight | Only exact pane-order option; split layout is not equivalent. |
| editorShowWordCount | Only final word-count visibility. MUST NOT map to showsStatusBar, which also hides line/column and other information. |
| editorWordCountType | Exact old/new enum conversion only; no raw-integer cast or invented counting mode. |
| editorScrollsPastEnd | Only exact final preference; otherwise report unsupported. |
| editorEnsuresNewlineAtEndOfFile | Suggestion only if separately approved final setting exists; do not enable byte-changing save behavior silently. |
| editorUnorderedListMarkerType | 0='*', 1='+', 2='-'; only exact preferred-new-list setting. Invalid enum rejected; existing source markers never rewritten. |
| previewZoomRelativeToBaseFontSize | Unsupported coupling unless final equivalent exists; editor font is not a proxy. |
| htmlTemplateName | Default is equivalent fixed-template policy only; other executable markup templates unsupported. Not an export-format switch. |
| htmlStyleName | Legacy CSS is not embedded/linked delivery. No arbitrary stylesheet import. |
| htmlDetectFrontMatter | Actual final parser policy; never blockDirectives. |
| htmlTaskList | Current E22 parser always supports task lists; false has no disable preference. No inert toggle. |
| htmlHardWrap | Rendering hard breaks differ from editor line wrapping; only exact final parser/render option. |
| htmlMathJax | Explain the engine/capability change; no MathJax runtime/URL/hidden switch. |
| htmlMathJaxInlineDollar | Explain #116's shared grammar and unsupported disabling behavior; no second grammar. |
| htmlSyntaxHighlighting | Export code highlighting, not source editor highlighting; map only a real matching control. |
| htmlHighlightingThemeName | Legacy HTML stylesheet, not an E23 theme ID; no unreviewed alias. |
| htmlLineNumbers | Exported code line numbers, NOT E22's source gutter. |
| htmlGraphviz | Report local Graphviz capability; no old scripts or no-op setting. |
| htmlMermaid | Same for local Mermaid. |
| htmlCodeBlockAccessory | Unsupported unless exact final enum semantics exist; no raw-value cast. |
| htmlDefaultDirectoryUrl | Never an access grant. At most a validated picker suggestion with explicit user selection; no background enumeration. |
| htmlRendersTOC | Explain explicit [TOC] contribution policy; never insert markers or rewrite documents. |

editorBaseFontName/editorBaseFontSize/editorBaseFont/editorUnorderedListMarker are calculated, not independent stored imports. filesToOpen/pipedContentFileToOpen are transient IPC and never replayed. Legacy window/split frames, NSGlobalDomain values and unknown Sparkle metadata are not bulk-copied. Any actually encountered prefixed/PAPreferences aliases need source-verified mapping, not suffix guesses. Preserve the original legacy domain byte-for-byte.

## Destination precedence and consent

Read persistentDomain(forName:), not dictionaryRepresentation with registered/global/argument defaults. Use the compatibility result above before deciding whether a destination field exists. An existing valid persisted value is protected even when equal to the default. A missing domain may be seeded; a known older domain is migrated without resetting unrelated fields. Unknown/corrupt data blocks automatic replacement rather than being treated as absent.

Show proposed applicable changes, retained deliberate settings, unsupported semantics and invalid inputs. Default import fills genuinely absent fields only when provenance proves absence. Replacement of existing fields requires explicit per-field selection. Preserve all unselected fields when serializing the whole domain. Revalidate destination revision/raw hash at commit; a concurrent settings edit requires re-planning its conflicts, not applying a stale summary. Do not silently rerun old import after the original app changes later.

Theme import uses E23's stable custom-ID Replace/Copy/no-op policy and safe validation. Repeating the same migration cannot generate another UUID/file. Record the source-theme-to-destination-ID mapping in the journal before insertion. Unknown legacy executable CSS remains unsupported, not misreported as a migrated theme.

## Restart-safe application and concurrency

One application settings-write coordinator serializes normal edits, compatibility migration and legacy import. #18's bootstrap must use the same admission boundary, not a second lock nobody else honors. Plan all domain/theme changes before writes and create a restricted local transaction journal recording mapping version, source hash, before/desired per-domain digests and theme IDs. No secrets/private preference values appear in public evidence.

Apply staged typed values, record each successful domain/theme operation and read it back. Completion is recorded only after all intended writes are acknowledged. On restart: equals desired means already done; equals captured before allows one planned write; any third value is a conflict to preserve/report. UserDefaults.synchronize does not establish multi-key atomicity. Failed/pending imports cannot be marked complete just because one Boolean persisted.

Decline is a separate opt-out state, not completed migration. Retry preserves already accepted changes, reports outstanding work and never modifies original MacDown. Rollback restores only unchanged transaction-owned destinations and never later user edits. Do not block ordinary safe editing indefinitely on optional legacy import; unsupported authoritative development state is a different #18 bootstrap recovery condition.

## Units, tests and completion

A. SETTINGS-COMPAT pure decode/migration and ordinary-store integration, with historical fixtures and no user-domain access. Final E22 field changes receive the same discipline.
B. Complete typed legacy map against final settings/theme interface; all declared keys and deliberate unsupported semantics covered. Consume E22 parser evidence without editing its work.
C. Immutable plan, consent, stable theme mapping and serialized journal implementation. Inject failure before/after every write/read-back/completion and simultaneous normal settings edits.
D. Existing first-run/Settings integration, all strings before final E16, full regression and real isolated-account migration via #88.

Tests include absent/false/default-valued values, pre-E22 blobs, missing fonts, invalid types/NaN/enum values, malicious URLs/IDs, Unicode names, unknown versions, source changes, repeated runs, partial recovery, consent races, theme ID collision and unchanged legacy domain. Verify actual live apply without relaunch and raw preservation of unsupported destination blobs.

Allowed areas: AppSettings compatible decode/import/store/tests; E17 bootstrap coordinator; existing Settings/first-run/catalog integration; E23 theme API. No original-app writes, E22 parser feature reimplementation or source normalization. Run serial format/strict lint, affected/full package/app tests and Release build, then real user-visible evidence. Stop on protected-value overwrite, unclassified equivalent key, non-idempotent replay or a security grant inferred from stored data.

Second review adds the missing-field migration prerequisite, prevents the word-count/status-bar false equivalent, binds theme retries to stable IDs and unifies bootstrap/settings writer admission. Architecture coverage is complete; final post-E22 field rebinding and runtime evidence are not claimed complete. #53 remains open until both its importer and E22-owned parser obligations pass in #115.
