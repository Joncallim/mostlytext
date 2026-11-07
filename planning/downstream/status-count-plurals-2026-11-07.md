# Use correct English character and word count forms

## Owner summary and baseline

At actual main6b49777d0f36c3d7a23cd0089e0823da1986660a, the normal Release status
bar displays “6 characters,1 words”. Its actual screenshot/AX/source receipt is
preserved in run42334704000. The canonical extracted key has two independent
64-bit counts but its English catalog value has no plural substitutions.
Correct the resource forms without changing metrics, document bytes or layout.
This is a bounded #3/#6 language fix, not final three-language acceptance.

## Ownership and interfaces

The app owns the existing %lld characters, %lld words key. Keep that key and
its source interpolation unchanged. Add independent English catalog plural
substitutions for characters (argument1) and words (argument2), preserving exact
argument types. One selects the singular noun; other selects plural. Existing
French/Japanese/Polish draft values and review states stay byte-for-byte equal
as parsed records. Do not silently mark them translated or claim final E16.

## First control and allowed execution

Before the resource change, compile the actual old catalog's English resource
into a private non-application bundle. A small reviewed Foundation-only console
resolves the exact source interpolation for all nine0/1/2 count combinations,
with explicit en locale and exact expected complete messages. Preserve actual
old failures, resource/source digests and compiler output. Inspect linkage before
executing: no AppKit, SwiftUI, WebKit, CoreText, font/drawing or application entry.
No Xcode app build/registration, native app-hosted test, owner data/defaults,
private signing key or protected CORTANA execution is permitted.

The same console and same expected nine messages must pass after the catalog
correction. This checks real compiled resources/Foundation resolution, not a
Python formatter or mocked localization function. It does not prove the native
app's final packaged bundle; a canonical app test and hosted full CI do that
at their own scope. No source test may be skipped or changed to accept bad grammar.

## Implementation and invariants

Only this architecture, the existing English catalog record, a new parameterized
case in EditorStatusBarViewTests and the existing generated localisation inventory
may change. The canonical app case covers empty, one-character/one-word,
multiple-character/one-word and multiple-word documents through actual view
countText. Retain all existing plural, CJK/emoji and UTF-16 assertions.
No new strings, dependencies, public APIs, state, renderer, parsing work or
resource/performance ceiling. Count formatting remains based on precomputed
metrics. Source identifiers/locale drafts/licence copy remain unchanged.

## Verification and integration

Write this architecture before implementation. First record the genuine old
compiled-resource failure. Then modify only the stated resource/test records,
compile again and execute the unchanged console, validate compiler keys/catalog
structure, refresh the generated inventory, and run strict changed-source style
and all relevant source/compliance controls. No local app test executes.

This source may be combined with the separately proved responsive status layout
after that branch's genuine first failure, preserving both exact unit histories
and writing the assembly decision before merging. Qualify the final combined
source once with complete hosted CI, normal public CLI, unchanged public focus,
new real narrow/wide regression and native theme controls. Intake actual main
before final qualification; do not relabel old receipts to a newer tree. Only
current expected-head merge and actual parent/tree proof authorize integrated
checkbox updates, followed by a live whole-issue audit.

## Limits

English resource resolution is not final native-speaker review, complete
non-English/pseudo/RTL layout, final freeze, protected owner-account or signed
artifact acceptance. All those original issue criteria remain open. A mismatch
in source key/type/resource ownership or an unexpected first outcome requires
a written correction before changing policy or assertions.

## Catalog representation correction before final acceptance

The first English candidate compiles and the unchanged real formatter passes
all nine cases, but the existing repository validator rejects four branch
placeholders: custom substitution names characters/words imply %characters/
%words in its admission model, whereas these branches use Apple's generic
%arg. Preserve that first successful formatter result and failed admission.
Use the repository's existing canonical arg1/arg2 substitution names with the
same argument1/2, lld types and %arg branches. No validator, assertion, language
review state or acceptance rule changes. Recompile/re-execute the unchanged
formatter for the corrected representation and require both actual resolution
and existing validator to pass before accepting the unit.
