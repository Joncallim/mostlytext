# Protected editor checkpoint: Release UI-test launch hooks

## Owner summary

The repaired private checkpoint started its UI runner, but the app deliberately
crashed when the first UI case requested `-UITesting`. The Release build had not
enabled the app's test-only launch hook, so Xcode could not attach to a process.
This change enables that hook only in the private checkpoint build and requires
the disposable UID 502 account for that build. Ordinary Release builds retain
their existing rejection of test arguments.

## First failure

The first `f90f5ed4e5b34e6b9d1f23fefce784d195eb94cb` protected result is
retained on [issue #5](https://github.com/Joncallim/mostlytext/issues/5#issuecomment-7207447093)
and linked from [issue #8](https://github.com/Joncallim/mostlytext/issues/8#issuecomment-7207450965).
The first two dead-key UI cases failed at app launch. Both app crash reports
show `EXC_BREAKPOINT/SIGTRAP` in `AppDelegate.validateUITestLaunch()` at
`AppDelegate+UITestLaunch.swift:43`; the tests supplied `-UITesting`, while the
private Release build only supplied `RELEASE_PREVIEW_PROBE`. That build
condition leaves `testHooksEnabled` false and makes the guard's rejection
intentional. The run was stopped after the repeated same-source crash; its
partial result and `FAIL` receipt are not a UI pass. The earlier `62b72` stage's
runner-bootstrap failure and 21 passing app cases remain separate evidence.

## Change and verification boundary

The checkpoint's pinned Release `build-for-testing` now supplies
`NATIVE_EDITOR_CHECKPOINT` in addition to its existing preview-probe condition.
That condition enables the existing raw launch-argument path and UI-test hook
only in the private build. The app refuses to launch under any real or effective
UID other than 502 when this condition is compiled. It does not enable the
separate #117 export acceptance command, change ordinary Debug or Release
behavior, or use the `UITEST_ISOLATED` bundle identity and path policy.

The owner must prepare a new exact merged-source stage and the unlocked test
desktop must run its staged acceptance path. A local compile can establish that
the build is valid and the intended condition was passed to the compiler; it
cannot establish a UI case result. Keep #5 and #8 open until the new protected
run, and keep formal signing, rights/source offers, final signed-artifact
reruns and publication separate.
