# Bind the normal application's authoritative preferences correctly

## Owner summary and baseline

Fix the demonstrated startup refusal without bypassing migration, consent or
persistence checks. Start from actual main c321e9735c091cb3871240ac1036f98085eb1858.
The ordinary app cannot finish optional-import inspection because its settings
store silently falls back to an unbound store. Select the standard defaults
object when binding the actual process's own bundle domain; retain named suites
for genuinely separate domains. Every authoritative read remains limited to
the saved domain. No owner application execution, signing or release occurs.

## Actual failure and reviewed decision

Unchanged-source1515 and54c8 normal Release launches fail both fresh and
configured CLI connection. Whole-install migration finishes, but the actual
Migration window remains. Derived diagnostic57a7 run42306169459 preserves the
original failure and captures12 events: both actual PIDs reach journal creation,
then LegacyEditorMigrationBootstrap refuses before binding. That initializer's
only throw is unboundDestination. All1594 canonical/executed source hashes,
24pins and the exact3-file observation recipe are independently reconstructed
against actual syntheticcheckoutccd83064 from current main plus57a7. No silent
logging assumption is used. Production main has none of those observations.

AppDelegate requests UserDefaultsAppSettingsStore(persistentDomainName: its
actual Bundle identifier). Its constructor always uses UserDefaults(suiteName:).
Apple explicitly prohibits passing the current application's bundle identifier:
https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)
A failed initializer currently falls back to the generic unbound store and later
fails the bootstrap guard. Do not remove that guard or weaken domain admission.
First demonstrate the platform behavior with a unique Foundation-only console
bundle, verify no AppKit/SwiftUI/WebKit linkage and no owner application launch.

## Ownership and failure boundaries

Only AppSettings' bound-store constructor selects the defaults object. Preserve
its exact domain validation first, the actual supplied domain identity, internal
bound initializer, saved-domain-only reads, conditional write/readback and all
journaling/locking/permission/consent policies. Exact case-sensitive equality
with Bundle.main.bundleIdentifier selects UserDefaults.standard; a different
admitted domain still requires its own available suite. Invalid/system/original-
MacDown domains remain refused. Do not accept an arbitrary defaults object and
claimed domain through a new public API. Generic injected stores stay unbound.
No new module, actor, callback, model, threading, persistence format, resource,
endpoint, API or dependency change. Existing failure semantics remain.

## Test and integration slices

1. Retain a Foundation-only real-current-bundle counterexample to the old named-
   suite call. Add an app-host regression that constructs the bound current-domain
   store and creates the real journal/bootstrap against a private generated
   directory without changing preferences. Keep invalid/unbound/custom-domain
   controls. Owner-native execution remains prohibited; syntax/compile-only and
   pure preparation controls are allowed locally.
2. Use the original normal-launch CLI harness on the hosted runner, with no
   derived source overlays or observation flag. Retain original six comparisons,
   identity/ownership/source/pins/deadline checks. Fresh first-run may independently
   reveal the Welcome/listener ordering issue; do not silently skip that failure
   or claim the whole CLI solved from configured-only success.
3. Run fresh complete normal CI, strict lint/format and compliance/inventory on
   the immutable source. Require the real new app test and complete package/app
   selections, all four app/publicCLI builds and original native CLI before/after
   receipts. Every expected comparison must execute and pass before claiming
   complete warm CLI behavior. A further real failure requires an explicit
   architecture revision and material correction, not an unchanged rerun.
4. Review exact current source, pins and all review threads; require source,
   synthetic and computed trees equal and every required check green. Merge
   against the expected head, verify actual parents/tree and clean canonical
   fast-forward, update bounded issue units and reevaluate the backlog after
   each metadata update. Keep unrelated Preview/parser candidates separate.

## Performance, interoperability and completion

No performance threshold, native deadline, text fidelity, source representation,
locale/string, accessibility or export behavior changes. Original preferences,
installation/session/recovery and external application stores are preserved.
This is a startup correctness correction, not owner migration, trusted cold CLI
launch, signed/notarized update, separate-account, final artifact or release
acceptance. Those original criteria remain open. DiagnosticPR112 stays a draft
and its observed source is never merged as a product correction.


## Actual isolated platform counterexample

The unique current-bundle Foundation console returns nil for the original
named-suite call and emits Foundation's explicit own-bundle refusal. The
corrected standard selection is the actual standard object; a different unique
suite is available. Bounded normal exit0, exact binary digest and no GUI-library
linkage are retained in evidence/current-domain-bootstrap-2026-11-07. No
preferences or app data are read/written by that console. The app-host test must
now demonstrate the actual bound store's empty-import ready callback and
unchanged saved preferences; the platform counterexample alone is not native
startup/CLI qualification.
