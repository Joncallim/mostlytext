# Maintaining MostlyText localization

This is the current source-maintenance workflow. The original E16 implementation
notes describe a historical catalog set and toolchain. Final localization and
native acceptance remain owned by [MostlyText #3](https://github.com/Joncallim/mostlytext/issues/3).
Follow the [two-candidate release sequence](../planning/RELEASE_SEQUENCE.md):
software stabilization, private candidate 1 and native verification, final E16,
then the final signed candidate and its artifact-sensitive reruns. An interim
catalog or compiler pass is not the final string freeze.

## Put the lookup with the copy's owner

App-owned Foundation values use `String(localized:)` with the app's main bundle.
Package-owned values use `String(localized: ..., bundle: .module)` and that
target's existing resource catalog. A String passed through a model, custom
parameter or `Text(verbatim:)` is already resolved text; wrapping it in a view
does not retroactively localize it. Localize static owned copy before storing
or passing it. Keep authored titles, filenames, document content, technical
identifiers and opaque renderer/system messages verbatim.

Literal SwiftUI labels and correctly typed `LocalizedStringKey` branches already
enter the pipeline. Conditional syntax alone does not imply a missing lookup.
Check the compiler's actual output rather than mechanically wrapping every
literal. Persistent naming rules, file-format codes and regex/case symbols
have separate contracts; translating a stored identity is not a UI-label fix.

Counts need a complete message and catalog plural forms. Do not build a label
by joining an English noun and `s`. Use the compiler-extracted key: signed
32-bit and 64-bit values, strings and different interpolation APIs can produce
different format specifiers. An escaped quote in a source literal is not an
extra backslash in the runtime key. Preserve placeholders and argument types.

Foundation grammar-agreement markup such as `^[...](inflect: true)` must resolve
through `AttributedString(localized:)` (or an appropriate Text initializer).
`String(localized:)` leaves that markup visible. A surface requiring a String
can use the resolved attributed value's `characters`; test the real count forms
and absence of markup. Catalog compilation alone does not establish this behavior.

## Validate and inventory source resources

Run from the repository root:

```sh
python3 -m unittest discover -s planning/downstream/tools -p test_localization_inventory.py
python3 -m unittest discover -s planning/downstream/tools -p test_compiled_string_coverage.py
python3 planning/downstream/tools/localization_inventory.py --check --check-transifex \
  --inventory-out planning/downstream/mostlytext-localization-inventory.json
```

The last command updates the tracked inventory; review that diff with the source
and catalog changes. It checks structure, interpolation and resource mappings,
not translation quality or an authorized Transifex account. Existing accepted
translations and review states must survive unrelated additions. English draft
values in non-English locales stay `needs_review` and are not advertised as
completed translation or three-language plural acceptance.

## Check actual compiler coverage

The hosted Release app/helper builds enable `SWIFT_EMIT_LOC_STRINGS=YES`. The
metadata step reads the actual Xcode `OBJROOT` and `CONFIGURATION`, then runs
the read-only [coverage tool](../planning/downstream/tools/compiled_string_coverage.py).
For a complete compile-only local build, use those actual settings:

```sh
python3 planning/downstream/tools/compiled_string_coverage.py \
  --extraction-dir '<actual OBJROOT>' --configuration Release \
  --output '<owned evidence directory>/compiled-string-coverage.json'
```

The tool requires a record for every owned app, helper and package Swift input,
including sources with no keys. It excludes dependency/test/resource-script
copy, compares architecture duplicates within the selected configuration and
checks exact catalog/key identity. Empty or partial extraction cannot pass.
Future extension targets must explicitly extend the coverage tool's ownership
and extraction roots before their compiler output can be claimed covered. The
current roots cover the app, helper and MacDownKit package.

Debug records cannot substitute for missing Release inputs. The receipt records
current source hashes and relative source/key/line routes; produce it from a
stable current build, not stale intermediates from a different source snapshot.

Add missing exact keys without silently overwriting or relabelling existing
translations from a similar escaped/format key. The compiler guard finds keys
already in the localization pipeline. A separate review of plain String models,
alerts, accessibility labels and undo names is still necessary.

Compile changed catalogs with the current Apple `xcstringstool`, then read the
actual built bundle resources as well as testing resolved values. English may
legitimately use source-key fallback without an explicit English resource entry;
record that distinction instead of mistaking fallback for a translated lookup.
Use distinctive separate resource sentinels and original-source controls to
prove bundle routing. Keep synthetic markers out of production catalogs.

Compile-only/resource checks do not launch the app. Native AppKit menus, panels,
VoiceOver and language/layout checks follow the protected-account prerequisites
in [acceptance status](../planning/ACCEPTANCE_STATUS.md); do not change the
owner's global language defaults as a shortcut.

## Exchange translations without losing reviewed content

All existing catalog resources are mapped in `.tx/config`; its organization and
project slugs remain unconfigured placeholders. A structurally valid mapping
does not prove a real account, successful synchronization or approved language
coverage. Use only verified authorized project identities, and keep credentials
out of source, command arguments and evidence.

Follow the [safe Transifex contract](../planning/downstream/issue-17-handoff.md#safe-transifex-workflow).
Stage source uploads and translation pulls in a disposable checkout, snapshot
source/comment/substitution/review-state digests first, and qualify a small
canary round trip with the actual installed CLI/API version. Source uploads can
carry embedded translations; stale local seeds must not overwrite reviewed
remote text. Validate returned keys, locales, placeholders, plural structure and
review states before merging. Do not commit a pull blindly or treat a translation
percentage as linguistic/native acceptance.

## Final evidence remains separate

Final E16 records the exact post-verification source/resource/UI baseline,
supported and reviewed locales, all resource-owner sentinel checks, three
materially different plural families, pseudo-localized/RTL layout stress, a
complete non-English native journey and native-speaker/VoiceOver review. Keep
earlier evidence immutable and rerun affected checks after later string, resource,
identity or packaging changes. Signing, exact final compliance and public source/
application promotion retain their own authorization and verification gates.
