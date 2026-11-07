# Establish whether the hosted Mac can exercise a real Quick Look provider

## Owner summary and current baseline

Find out whether the remaining Quick Look work can progress without the owner's
protected desktop. Current main is4ed1cfc6137644f84c55372bbdf3c991ba621a89.
Its real theme, parser, math and heading units are integrated; the root project
still has NO Quick Look extension. Startup PR117 is independent and must finish
its own first qualification unchanged. This is a small pre-implementation
platform probe, not a shipping extension or a new document renderer.

The binding E23 handoff's QL-REPLY gate still precedes shared rendering. Local
API compilation already establishes the explicit QLPreviewingController
conformance and synchronous data factory; no registration or native call has
occurred. This unit asks ONLY whether a real minimal ad-hoc sandboxed data
provider can be discovered and called from cold Finder on disposable hosted
macOS26. A negative result is retained as a feasibility result, never a passed
Quick Look gate. Owner-account GUI execution remains held.

## Ownership and allowed execution

All fixture code lives below .github/quicklook-reply-probe, with its own generated
Xcode project, dummy containing application and cross-application UI test. The
root product project, packages, app, renderers, pins, defaults, support data,
artwork and document handlers stay unchanged. Do not run the production app.
The containing fixture uses the frozen app identity and the provider uses the
reserved app.mostlytext.MostlyText.QuickLook identity solely on an ephemeral
hosted runner. Neither claims a document handler/default. Register only the
existing net.daringfireball.markdown type. No public.text/data takeover.

Runtime scripts and UI tests require the actual /Users/runner account and
macOS26; preparation refuses without GitHub's hosted-runner environment. Local
work is source review, syntax/type checks and compile-only. Use ad-hoc signing
of this private fixture only, without accessing a Developer ID/private key,
notarization profile or public release channel. Sandboxed extension has only
user-selected read-only file access; no network or App Group entitlement.
Never grant TCC, edit its database, prompt the owner or seize defaults.

## Dependency-ordered narrow slices

1. Create one tiny static provider plus immutable HTML and original PNG bytes.
   Its actual providePreview method records callback thread, selected-file
   bounded-read outcome, a generated sibling-open result, reply and factory
   invocations through a private logging subsystem. Do not assume any parent
   directory permission from a URL. Refuse inputs outside the exact hosted
   generated fixture and do not emit authored source or private data to logs.
2. Build and ad-hoc sign the containing fixture and provider. Verify actual
   bundle identifiers, extension point/data-provider/Markdown declarations,
   sandbox entitlements and binary hashes. Register that exact extension with
   PlugInKit on the disposable runner; never call a default-handler setter.
3. Reveal the generated Markdown fixture in real Finder, with no containing
   fixture launch. A bounded cross-application XCUITest must actually select
   that file and invoke Space. Require actual visible provider marker and a
   screenshot. If macOS refuses UI automation, registration or the callback,
   preserve the actual outcome and stop. A qlmanage or mock call cannot replace
   this cold-Finder criterion. Avoid command retries and longer deadlines.
4. Collect actual provider logs, complete build/test logs, xcresult, source and
   generated-input manifests, process identities and resource/file hashes.
   Check the container never launched; describe timing/callback/visible output
   only to the extent observed. Build success, discovery and actual Finder
   invocation are separate results.

## Required verification and subsequent gate

Syntax/type-check the exact provider against the installed SDK without executing
it locally. Verify project generation/Info.plist/entitlements/source hashes and
that the entire root MacDown2 graph remains byte-identical to main. Run ordinary
compliance and diff checks. First hosted outcome is immutable; no unchanged
native retry. A fixture defect requires a written correction with a controlled
counterexample before another materially different attempt.

This first bounded probe does NOT satisfy all QL-REPLY requirements: actual system
cancellation, repeated factories/retained payload accounting, failure-once and
fallback while a real worker is slow still require subsequent named probe
slices. Broad shared presentation or production target work stays held until
that complete platform gate passes. Source fallback, capacity leases and the
existing original deadlines remain binding, without an invented cancellation
callback or false assertion that returning a reply releases memory.

A diagnostic-only draft is never merged as a production fix. Only accurately
scoped reusable probe/evidence changes may later integrate after actual review
and ordinary CI; no whole issue is closed from this unit. Reevaluate the live
backlog after each issue update and preserve all native/rights/publication/exact
release criteria.

Primary platform references: Apple QLPreviewProvider documentation and
QLPreviewReply's data-factory initializer, read7November2026. Their declared
interfaces are checked against the actual compiler/SDK; neither documentation
nor compiler success substitutes for native Finder evidence.
