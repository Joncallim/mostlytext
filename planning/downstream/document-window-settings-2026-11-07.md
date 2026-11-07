# Apply the shared settings to each real document window

## Owner summary

Imported and changed editor preferences must affect the actual editor, including restored tabs. A normal Release migration restored the documents and recovery correctly but displayed Spaces4 despite authoritative imported indentation2. Connect the existing shared settings object to each document window's own hosted view. Verify both initial preferences and live changes across windows. No migration-policy, dependency, storage, menu, namespace or data-preservation change is needed.

## Baseline, concrete failure and ownership

Actual main ef93ab2d remains unchanged. Frozen PR130 source4b671790 produced actual synthetic b6145109/tree34ad6aa9 and failed first run42359122943 at the unchanged Spaces2 assertion. Complete first evidence and independently verified actual source/pin/generated/compiled/result/owned records are in evidence/normal-migration-settings-first-2026-11-07. Old profile and all other preference domains remain intact; first normal Quit/relaunch are NOT_RUN. Preserve the failed outcome; no identical retry.

WindowController constructs a separate NSHostingController with WorkspaceShellView. That root injects windowCoordinator but not appSettings. The SwiftUI scene environment does not belong to this separate root. Both shell and editor read optional appSettings; status fallback is4. The coordinator already owns the same application settings model used by commands and Settings. Install precisely that model at the real hosting boundary. No new model, defaults reload, notification, cache workaround or changed conservative preference policy.

## Contract and permitted implementation

Add .environment(\.appSettings, coordinator.appSettings) to the WindowController shell. Keep all existing environment values and initialContentController injection unchanged. Allowed production file: MacDown2/MacDown2/WindowController.swift only. No AppDelegate, scenes, package, public API, defaults, source admission, pins, runtimes, notices or SBOM edits in this unit.

Add an app-target Swift Testing mounted-window regression using a unique defaults suite and owned temporary recovery directory, existing coordinator/window/editor path, explicit editorOnly layouts and NoOpSessionStore. Verify two distinct real window roots use non-default font size and indentation, then both consume a live model change; a subsequently created window must receive current values too. Await bounded native view updates on MainActor without spin,5s per stage; close/remove all controllers and owned files/domain on every exit. Do not manually inject settings into the test view, call editor.apply, or directly mutate an editor configuration: the production hosting boundary must be under test. Existing no-window helper tests do not prove that boundary.

All ownership and observation remain MainActor. Setting changes already publish through AppSettingsModel and SwiftUI Observation; no new cancellation tasks/state machine. Editor-only fixture avoids unrelated Preview/renderer state; no source text mutation. Existing read-only unsupported-domain policy remains. No new UI strings, accessibility or export behavior.

## Verification, publication and completion

Keep original frozen PR1304b671790 and all first companion/matrix outcomes intact until every outcome is retained. Source syntax/style and narrow source/runtime admission controls can run on CORTANA; no local app/CLI/AppKit/SwiftUI/font/WebKit/package build. New mounted regression and existing unchanged normal migration/relaunch/normalQuit checks execute only on guarded disposable hosted macOS26ARM. New test compilation and runtime are unverified until actual first native execution.

After all prior outcomes are retained, intake this reviewed unit as real ancestry into PR130, publish one new final source and require fullCI/package/app/Debug+Release app+CLI builds, all38original methods/3critical, normal CLI/focus/status/licence, ownership4 and full normal migration with current2→8 relaunch. Keep every old assertion and budget. Retain and diagnose any new first failure before correction. Update canonical issues with proved criteria only, audit all open issues after each metadata mutation, then expected-head merge and verify actual parents/tree. Preview/future-session remain separate pending units. Protected owner/installed/quarantined/signed release, VoiceOver, native locales and rights acceptance are not established by these engineering checks.

## Prepared source verification

Local correction586da1ec keeps the original normal migration2→8/native recovery assertions unchanged. Complete format0/1490, strict lint0, Swift syntax,9original UI inventory,7migration filesystem/admission and3optimized literal Foundation seed controls pass. Source Compliance reports0unverified; all332 compliance controls pass in42.991s. The mounted regression has not compiled or executed yet. Complete old4b first outcomes must be retained before new publication; runtime success and merge remain pending.

## Focused first native intake before final expansion

The separate compact-chooser architecture now specifies a focused first native spike on the reviewed combined branch after every frozen4b first outcome is retained. Preserve both source units as actual ancestry, keep PR130 frozen during that spike, and explicitly dispatch the unchanged existing3critical and normal-migration workflows. This tests the two new assumptions before expanding to a complete new matrix. Any first failure remains failed and requires evidence-led material correction. Passing that spike does not replace fresh fullCI/38original/3critical/public/ownership/migration final-source qualification and review before actual PR130 merge.
