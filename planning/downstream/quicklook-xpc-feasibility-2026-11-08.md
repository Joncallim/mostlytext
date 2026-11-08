# Test whether Quick Look can reach a bundled XPC service

## Owner summary and baseline

The real Finder provider can read its selected file, but its attempt to run a
signed embedded command-line helper is refused before the helper starts. PR #152
retains the complete failed run and remains draft. This private experiment asks
whether the same Finder-hosted provider can instead request one fixed response
from a system-launched XPC service bundled with the containing fixture app.
Nothing in this experiment renders a user document or changes the product.

The design baseline was main `a46c57c4b62376b67492cf67421a4961fdf55c1c`. PR #152's
actual first failure at run 42433239533 is `NSCocoaErrorDomain` code 4,
`access(X_OK) == -1`, `errno == EPERM` for the mode-0755 embedded helper.
The original cold static and JavaScriptCore Finder cases passed; neither worker
case reached a child. The failed result is not reclassified as a service result.

Apple documents bundled XPC services at `Contents/XPCServices`, started by
`launchd`, with connections by service bundle identifier. Its older guide also
says a private bundled service is available to its containing application. The
documentation does **not** establish that a Quick Look app extension hosted by
Finder can connect to that service. That compatibility question is the reason
for this spike, not a premise of production design. Sources:

- <https://developer.apple.com/documentation/xpc/creating-xpc-services>
- <https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle>
- <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html>

## Fixed interface and trust boundary

Use only the existing private `.github/quicklook-jsc-probe` fixture. Add one
service bundle to the containing app at the standard XPCServices location, with
its own sandbox and no file, network, app-group, global Mach lookup, temporary
exception, JIT or debugging entitlement. Keep the provider's exact sandbox and
user-selected-read-only entitlements. No document path, bookmark, file bytes,
script, engine, executable name or environment reaches the service. The provider
sends one fixed `ping` message with a positive request ID. The service replies
with a fixed marker, that request ID, its real process ID and current entitlement
facts. The service refuses nonpositive or repeated IDs per connection. The
provider admits only a matching ID, fixed marker, distinct process and sandbox
result; the interface has no variable-size document or script field. The
provider records whether connection/launch and reply succeeded, and returns a
frozen fixture-only HTML marker only on a verified response.

The connection is a public, ordinary bundled-service API. Do not add a Mach
service registration, app group or permission if the extension cannot connect.
Do not use the app container as a relay or launch it in the background. A failed
lookup/launch under unchanged authority is an answer to this question.

## Execution and failure policy

Run only on a disposable hosted macOS 26 ARM runner with the existing owned
Finder executor. Preserve original cold/static and JavaScriptCore source and
tests byte for byte. Add a third fixed fixture and actual Finder test. On this
private branch, adapt the **already registered**
`.github/workflows/quicklook-jsc-probe.yml` path to manual-only execution of all
three genuine cases, retaining the two original controls. GitHub requires a
manually dispatched workflow path to exist on the default branch; a new
branch-only workflow file cannot be triggered this way. Capture all source and
generated inputs, every
regular file in the actual signed app/provider/service/test bundles, exact
entitlements, full native result, provider/service logs and first workflow
artifact before any correction. The original no-container-launch check remains.
The existing execution hold forbids local app, helper, XPC, JavaScriptCore,
Xcode product or SwiftPM runtime. Local work is limited to source review, C/Swift
syntax and SDK type checking, pure source controls and compliance.

A connection error, timeout, service crash, wrong process/identity, unexpected
entitlement or changed original case fails the spike; it is never converted to
a skip or a successful fallback. One harmless successful ping proves only that
the service can be reached from this provider under the tested host. It does not
prove independent hard deadlines, service termination, memory budgets, renderer
containment, untrusted-input admission, final signing or release acceptance.
Those require a separate architecture and physical-retirement proof.

## Slices and stop conditions

1. Commit this architecture before any service or provider implementation.
2. Add the fixed service, connection and single Finder control in this isolated
   branch. Check source inventories, standard bundle placement, compiled
   entitlements, original-case preservation and pure outcome parsers.
3. Publish and dispatch only after independent source review and the guarded
   hosted workflow are ready. Preserve the first complete result before change.
4. If the actual Finder extension cannot connect, record the precise refusal
   and stop. PR #152 stays draft; neither issue #7 nor #8 closes on this spike.

This is an engineering feasibility slice for issue #7. It has no user-visible
string, accessibility, localization, export or document-format change.

Workflow dispatch path rule: <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch>.

## Source preparation checkpoint

The isolated branch changes no `MacDown2` file and no original static or
JavaScriptCore Finder test. The installed macOS 26 SDK strictly type-checks the
provider, service and new XCTest source. XcodeGen source generation places the
service bundle in the containing app's `Contents/XPCServices` copy phase; no
product was built or launched locally. Five new pure XPC correlation controls,
12 original JavaScriptCore controls, 13 observer controls and three owned-process
controls pass. Strict SwiftLint, pinned SwiftFormat, plist/metadata syntax,
source diff checks and tree compliance pass. The first Finder result, service
launch/reply, actual compiled entitlements and signed-bundle contents remain
**NOT_RUN / NOT_VERIFIED** until the guarded hosted execution. No conclusion
about Quick Look's ability to connect to the service is drawn from source checks.

## First hosted result and bounded evidence correction

The first hosted run [42488148446](https://github.com/Joncallim/mostlytext/actions/runs/42488148446)
at `e0f24f82e9409a0b5bc87ce3469f43eb8645df1f` failed before Finder registration
or native UI execution. Its standalone fixture built and was ad-hoc signed, but
`--seal-built` rejected the signed XPC service because its parsed entitlements
were not exactly `{com.apple.security.app-sandbox: true}`. The script discarded
that parsed value before raising, so the first artifact contains the source
entitlement, build log and provider entitlement but not the service's actual
signed entitlement. The whole first artifact ZIP, workflow logs and run status
are retained at `/Volumes/Fast SSD/CORTANA-Builds/quicklook-xpc-feasibility-20261108/first-e0f24f82`.
No XPC reachability or Finder result exists from this run.

The next private diagnostic change writes the raw `codesign --display`
output and parsed signed-service entitlement to the already captured hosted
artifact directory *before* retaining the same exact entitlement comparison.
It adds no entitlement, permission, service behavior, product code, timeout or
fallback. A new hosted run must disclose the actual mismatch before choosing
any correction; an extra signed entitlement remains a failure. Preserve that
run's complete first result before editing again.

## Second hosted result and signing repair architecture

The diagnostic run [42514915606](https://github.com/Joncallim/mostlytext/actions/runs/42514915606)
at `84f210892a21e5c07b30089588c50c6d4fc455e4` also stopped at
`--seal-built`, before Finder registration. Its retained
`xpc-service-observed-entitlements.plist` shows the signed service has sandbox
`true`, a temporary read-only exception for `/`, and temporary Mach lookups for
`com.apple.testmanagerd`, `com.apple.dt.testmanagerd.runner` and
`com.apple.coresymbolicationd`. The source `XPCService.entitlements` has only
sandbox `true`. The hosted `CodeSign QLReplyProbeXPCService.xpc` command used
Xcode's generated `.xcent` file, so the extra rights were introduced in the
test build's signing inputs. There is no evidence that the XPC service requires
them. The exact-entitlement verifier correctly rejected this result; neither
hosted run tested XPC reachability.

The next private fixture change will re-sign only the **embedded copy** of
`QLReplyProbeXPCService.xpc` with the exact sandbox-only source plist. It will
run as the containing app target's final build script, after both embed copy
phases and before Xcode signs the containing app. The service target's original
signature may still include test rights, but that unembedded build product is
not the service the app will install. The provider target is signed before the
app's embed phase and is not altered by this repair. The existing `--seal-built`
step will still verify the final app signature and the service's exact signed
entitlements, then capture every compiled execution input before native tests.
The script will require the exact hosted fixture paths and source plist, refuse
unexpected bundles or rights, and record the pre-correction service entitlement
for diagnosis. No product source, provider authority, service API, test case,
timeout, workflow trigger or fallback changes.

This is consistent with keeping test-runner instrumentation on the separate
automation host and UI-test targets. The XPC service is a fixed-response app
service, not a UI-test runner. If Xcode's generated rights are nevertheless
needed for this host to launch or connect to it, the genuine Finder case must
fail and retain its actual error; the rights must not be restored to make this
spike pass. Source-only validation must confirm the generated build-phase order.
The next hosted result must confirm the app remains validly signed, the embedded
service has exactly sandbox `true`, and the original two controls still pass
before drawing any conclusion from the third case.
