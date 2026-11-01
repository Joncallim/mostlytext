# UI test isolation: source and compile evidence

Source: `b7ad0e30dcebe5897eac9319468b0ab36783f906`.

CORTANA, macOS 26.5.1, Xcode 26.6, arm64. The source snapshot was
archived before generation; all 1,749 tracked file hashes were unchanged
after the builds, and the generated workspace lock matches Package.resolved.

- Isolated app/runner/test build-for-testing and static identity/signature/
  source-manifest checks pass.
- Normal Debug app/test compilation passes (180.77 seconds).
- Normal Release app build passes (174.16 seconds).
- Normal Release CLI build passes (4.90 seconds).
- The standalone Foundation/Darwin launch guard has 42 passing controls.
- The read-only Python preflight helpers have 13 passing fixture tests.

No application or UI test was launched by these checks. A separate account
identity/access-denial check proved the non-admin test UID cannot open the
protected owner home locations. That process did not launch AppKit or the app,
and therefore does not establish a usable isolated GUI session.

The proposed benign AppKit control was cancelled before its authenticated
launch when the owner stepped away. Runtime controls and the first single UI
test remain held. The fixed runner intentionally has EXECUTION_HOLD enabled.
Do not run an ordinary app in the protected owner's login to work around it.

Two unsupported verification recipes are retained: Release build-for-testing
fails because dependencies lack enable-testing, and adding that flag exposes
existing DEBUG-only test fixture APIs. Normal Release builds and Debug test
compilation pass separately. No DEBUG flag was added to Release.

This is a partial #88 implementation and evidence record. It does not close
#88, establish whole-app isolation, or satisfy a downstream native gate.

## Complete source binding correction

Review found that the advisory preflight checked the archive's complete source
manifest, but compared only six candidate paths. It now requires the candidate
worktree's HEAD to match the receipt and compares every tracked and nonignored
untracked input, including package resources and the committed lockfile, against
the complete archived manifest. Missing, extra or changed inputs fail closed.
Noncanonical paths, duplicate members, invalid digests and symlinked inputs are
rejected. Ignored generated products are omitted; tracked ignored inputs remain
included. The fixed runner additionally requires and compares sourceSHA and
sourceManifestSHA256. Historical receipts and logs above are unchanged; they do
not validate a later candidate. A new build/receipt is required for that source.

New fixture controls cover changes outside the former six paths, inventory
changes, malformed/duplicate manifests, symlinks and fixed identity mismatch.
They are included in hosted Compliance; their result must be recorded against
the corrected head before integration. No new local application, UI test or
owner-data probe is part of this correction. EXECUTION_HOLD remains unconditional.
