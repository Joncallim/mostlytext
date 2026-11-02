# Shared editor settings admission — 25 October 2026

## Owner summary

The app and a future original-MacDown preference importer now have one
read-only way to interpret stored editor settings. An explicit stored `false`
remains the user's choice, a historical blob missing only the later status-bar
field remains readable, and malformed or future data stays at its original
key while the current session uses safe defaults. This does not request
consent, import an old preference or write a migration.

## Exact local candidate and checks

- Branch `fix/53-legacy-preference-snapshot`, production checkpoint
  `9291b0c4` (based on integration source `e2434fab`). The earlier pure
  decoder checkpoint `19a10c0b` received independent source review with no
  actionable finding. The startup integration has not had independent review.
- `LegacyEditorDestinationEvidence` validates raw editor JSON before exposing
  a typed value, field-presence evidence or byte digest to an import plan.
  `UserDefaultsAppSettingsStore.editorStoredDomain` checks `object(forKey:)`
  first, so present non-Data values cannot be mistaken for absent values.
  Ordinary editor startup and write protection consume the same decoder.
- The first focused integration run found a real compatibility mistake: a
  declared schema-1 blob without the later `showsStatusBar` field was rejected.
  The correction admits it as known compatible and defaults only that absent
  field. The existing version-1, explicit-false, malformed, future and raw
  preservation tests pass afterward.
- The final locked, explicit-serial package run exited successfully: 2,715
  tests in 373 suites passed with only the two already-known Neon
  replacement-edit issues. Log: `/tmp/mt53-ci-serial-full.log`. A focused
  38-test AppSettings selection passed at this source. Strict SwiftLint,
  SwiftFormat and diff checks passed. The locked Release package build also
  passed (`/tmp/mt53-shared-admission-release-build.log`).

## Limits and next review

Tests use isolated disposable `UserDefaults` suites; no real user preference
domain was read or changed. An unreadable primary may keep its existing
one-time backup on an attempted ordinary save, but remains at the primary
key. Independent review must cover the new startup/integration delta before
it is combined with the app candidate. Consent, the serialized settings
writer, transaction journal/recovery, remaining legacy-key mappings, theme
destination, E17 rehearsal and native release acceptance remain open.
