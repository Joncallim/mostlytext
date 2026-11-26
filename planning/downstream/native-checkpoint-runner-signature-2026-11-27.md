# Protected native checkpoint: runnable local test products

## Owner summary

The first protected run of the private Release checkpoint reached the test
desktop and passed 21 app cases, but Xcode killed the UI test runner before it
could start a case. The staged runner's bundle signature failed local
verification. This change asks Xcode to sign the private test products for
local execution and rejects an invalid app or runner before it is staged or
launched. It does not sign a release candidate or change the product's release
identity.

## First failure and repair

The original stage for merged source `62b72d3a3923b8e2081e36b43c0d97ccfc5e24a1`
remains immutable. Its first protected result is recorded on [issue #5](https://github.com/Joncallim/mostlytext/issues/5#issuecomment-7197605394),
with the 21 passing app cases and scoped measurements on [issue #12](https://github.com/Joncallim/mostlytext/issues/12#issuecomment-7197612293).
The result bundle reports one UI-runner system failure, no skipped cases and no
executed UI case. The runner failed `codesign --verify --deep --strict` with
"code has no resources but signature indicates they must be present". This is
a strong execution-path lead, not a proved explanation for the signal kill;
crash-report collection was denied on the test account.

The checkpoint's Release `build-for-testing` now uses Xcode's `Sign to Run
Locally` ad hoc identity. Both the app and UI runner must pass deep, strict
signature verification and report an ad hoc identity before the product
manifest is recorded, after copying, and again before acceptance. No developer
certificate, notarization, production signature, or publication is involved.
The formal signing gate remains issue #4.

The pinned Xcode test plan must point to these exact verified app and runner
paths and to their expected test bundles. The prior prefix-only check could
accept an alternate in-root product that had not passed signature verification.
An independent review caught this before the PR was published; the new
negative plan fixture fails against the old check and passes with exact paths.

The owner's first preparation attempt also exposed a macOS path-alias bug:
an internal product link under `/var/folders` resolved through
`/private/var/folders` and was rejected as escaping. The manifest now
canonicalizes its root before checking resolved links. A regression fails on
the original guard, then passes with the repair; an external link still fails.
The original preparation logs and environment workaround remain in the
[issue #8 staging handoff](https://github.com/Joncallim/mostlytext/issues/8#issuecomment-7197292911).

## Verification and remaining work

- The `/tmp` alias, external-link, and exact-plan checks pass (3/3).
- A pinned optimized Release `build-for-testing` with the new Xcode signing
  settings completed. Deep, strict verification passes for its app and UI
  runner; a copied read only runner also verifies. The original stage fails
  the new signature check, as expected.
- No UI case has yet run on a stage built from this change. The owner must
  prepare a new exact-source private stage after merge, then the separate
  unlocked test desktop must run the staged acceptance path. Preserve the
  original failed result; do not reuse or replace its stage.
- Signing, third-party rights and source offers, exact final-artifact tests,
  and publication remain separate release gates.
