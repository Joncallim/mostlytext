> Implementation notes for [EPIC-16] Localization: String Catalogs + Transifex migration.
> See `planning/epics/EPIC-16-localization.md` for the epic's scope and acceptance criteria.

## Current maintenance entry point — 4 November 2026

Use [the current localization guide](../docs/LOCALIZATION.md), the live
[MostlyText #3](https://github.com/Joncallim/mostlytext/issues/3) criteria and
[the adopted release sequence](RELEASE_SEQUENCE.md). The ten-catalog counts,
extraction/tooling observations and old Transifex walkthrough below describe
the original September implementation. They are not current compiler-key or
translation acceptance. Current owned catalogs include later editor, CLI,
encoding and search resources, with explicit unreviewed language deltas.
Final E16 follows private candidate 1/native verification; no final freeze is
claimed by interim source checks.

## Historical architecture summary

MacDown 2's user-facing strings live in ten String Catalogs (`.xcstrings`):

- `MacDown2/MacDown2/Localizable.xcstrings` — the app target (views, menus, alerts, panels).
- One per SPM package target that has user-facing strings: `Workspace`, `FileTree`,
  `JSONSupport`, `Contributions`, `TextFilters`, `Diagrams`, `DiagramsD2`, `DiagramsGraphviz`,
  `ExportService` (all under `MacDown2/Packages/MacDownKit/Sources/<Target>/Resources/`).

Each package catalog requires that target to declare `resources: [.process("Resources")]` in
`Package.swift` — without it, SwiftPM does not generate a `Bundle.module` for that target, and
`String(localized:)` calls inside it silently fall back to the English source literal on every
locale, with no build error. This was a real, discovered gap (fixed in PR #110): 8 of 9 package
targets had none of this three components until then.

**Extraction limitation (verified, not assumed):** `xcodebuild -exportLocalizations` only scans
the app target's own sources — it does not scan SPM package sources at all, and it does not
reliably see through custom `View`/function parameters even when correctly typed. Two extraction
mechanisms are used to work around this:

1. For the app target, `xcodebuild -exportLocalizations -project MacDown2.xcodeproj -scheme
   MacDown2 -exportLanguage en` remains the primary tool — it side-effect-updates
   `MacDown2/Localizable.xcstrings` and reports `warning: ... non-literal key` for any bypass.
2. For everything else (packages, and as a fast substitute for the app target when a full
   scheme build is impractical — see "Known local tooling limitation" below), use
   `xcrun xcstringstool extract --modern-localizable-strings --output-format xcstrings --append
   -o <Resources dir> <source files...>`. This performs lightweight source parsing without a
   full build or package resolution, and is the tool of record for catalog maintenance in this
   repository going forward.

**Known local tooling limitation:** on this development machine, `xcodebuild
-exportLocalizations` (and other full-scheme `xcodebuild` invocations) can hang indefinitely at
"Resolve Package Graph" after sustained build activity — a pre-existing local daemon issue,
unrelated to project correctness. CI's `swift build`/`xcodebuild test-without-building` runs are
unaffected. When this hang occurs, `xcstringstool extract` (which does not invoke `xcodebuild` at
all) is the fallback for verifying extraction coverage.

## String Catalog key format (verified empirically)

`String(localized: "text \(x)")` computes its catalog key by replacing each interpolation with a
format specifier that depends on the **static type** of the interpolated value, not a uniform
`%@`:

| Interpolated type | Format specifier |
| --- | --- |
| `String` | `%@` |
| `Int`, `Int64` | `%lld` |
| `Int32` | `%d` |
| `Double` | `%lf` |

(Verified with `swift` directly: `String.LocalizationValue("... \(value) ...")` prints its
resolved `key:` component for each type above.) `SwiftUI.Text("text \(x)")` uses
`LocalizedStringKey` interpolation instead, which was independently observed to use `%@`
uniformly regardless of type (e.g. `Text("Line \(line), column \(column): ...")` → catalog key
`"Line %@, column %@: %@"`). These are two different interpolation protocols; do not assume one's
key format from the other.

## Automatic Grammar Agreement (`^[...](inflect: true)`) — resolution API matters

Foundation's `^[\(count) item](inflect: true)` markup is **only interpreted by
`AttributedString(localized:)`** (and SwiftUI `Text`, which uses the same markdown-attributed
parsing). Plain `String(localized:)` returns the markup unresolved as literal text — this was
found as a real bug in `PreviewContributionAdmission.swift`'s preview-budget diagnostic, which
built the message with `String(localized:)` and stored the raw, unresolved
`^[3 valid placement](inflect: true) exceeded...` markup into a plain `String` field displayed via
`Text(verbatim:)`. Fixed by resolving through `AttributedString(localized:)` and converting to a
plain string (`String(attributedString.characters)`) at the point the diagnostic is constructed,
so the count-correct, locale-correct text is what gets stored.

The catalog key is unaffected by which API resolves it (both read the same
`String.LocalizationValue`). For a locale that doesn't have Foundation's built-in English-style
morphology engine, the catalog needs an explicit plural variation using the standard
`.xcstrings` substitution schema:

```json
"^[%lld valid placement](inflect: true) exceeded the preview budget and remain as authored source" : {
  "localizations" : {
    "fr" : {
      "substitutions" : {
        "arg1" : {
          "argNum" : 1,
          "formatSpecifier" : "lld",
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "%arg emplacement valide ..." } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "%arg emplacements valides ..." } }
            }
          }
        }
      },
      "stringUnit" : { "state" : "translated", "value" : "%#@arg1@" }
    }
  }
}
```

Verified structurally correct with `xcrun xcstringstool compile <file> --output-directory <dir>
--language <locale>` (compiles to a proper `.stringsdict` with `NSStringPluralRuleType`) — this
is the validation step to rerun after hand-editing any plural entry, since Xcode's own String
Catalog editor is not scriptable.

## Priority locales: current status

Per the epic's acceptance criteria ("at least one shipped non-English locale... without
release-blocking clipping/truncation/untranslated critical UI" and "pluralised strings correct in
at least three materially different plural-rule languages"), three locales have been seeded with
real (maintainer/AI-authored, not yet professionally reviewed) translations across all ten
catalogs, chosen specifically to cover three materially different CLDR plural-rule families:

- **French (`fr`)** — CLDR "one" applies to 0 and 1 (differs from English's "one" = 1 only).
- **Polish (`pl`)** — four plural categories (`one`/`few`/`many`/`other`).
- **Japanese (`ja`)** — a single category (`other`); no grammatical plural distinction.

The one pluralized string in the app (`PreviewContributionAdmission`'s preview-budget diagnostic)
has explicit, verified-compiling plural variations for all three.

**Translation quality disposition:** these are functional, complete-coverage translations
authored without native-speaker/professional QA. They satisfy the epic's letter (a real,
non-English locale is fully exercisable; plural rules are exercised in three families) but not a
production-quality bar. **Native-speaker review of fr/pl/ja is a pre-1.0 release prerequisite**,
tracked the same way as E15's carried-forward icon/VoiceOver prerequisites — it does not block
engineering work, but it must be cleared before a production 1.0 ships.

The remaining priority locales (`zh-Hans`, `zh-Hant`, `de`, `es`, `ko-KR`) are architecturally
ready (same catalog infrastructure) but have no seeded translations yet — this is honestly scoped
as future community/Transifex contribution, not a 1.0 blocker per se, since the acceptance
criteria only requires "at least one" shipped locale plus the three-plural-family check.

## Current translation-exchange contract

The resource layout in `.tx/config` is checked against all current owned catalogs.
Its account/project slugs are placeholders, not verified remote identity. Follow
[the current guide](../docs/LOCALIZATION.md#exchange-translations-without-losing-reviewed-content)
and [the adopted safe exchange contract](downstream/issue-17-handoff.md#safe-transifex-workflow).
A real authorized project and a version-qualified staged canary round trip are
required before synchronization. Preserve source keys/comments, all non-target
locales, placeholder/plural structure and review state. Do not commit returned
catalogs blindly, let stale embedded translations overwrite remote reviews,
put credentials in evidence, or mutate owner language defaults for native QA.
The original legacy source reference is the frozen Git tag recorded in
[AGENTS.md](../AGENTS.md), not a current legacy-reference directory.

## Final string-freeze baseline remains open

The final English source-string set is frozen only after the post-stabilization
E16 review in [RELEASE_SEQUENCE.md](RELEASE_SEQUENCE.md). Record that exact
baseline in the release evidence then; earlier catalog snapshots are historical
and no final baseline is claimed here. Any subsequent application string or UI
change reopens the affected extraction, translation, layout and exact-artifact
checks in the current guide.
