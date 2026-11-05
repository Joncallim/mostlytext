# Remove owned compiler diagnostics without weakening regression checks

## Owner outcome and baseline

The complete PR93 run on d98c2fb6 records seventeen distinct owned compiler
warnings; a newer local compiler also warns about an unchanged weak sentinel.
This follow-on is based on PR93 source9c3d6358 and changes only those call sites.
Keep launch/account/private-path restrictions, runtime dependencies, notices and
all existing behavioral assertions. Native owner-account execution stays held.

## Binding correction

Decode bounded POSIX CChar buffers through their bytes up to the first NUL,
using the standard UTF-8 replacement decoding semantics already used by the old
String(cString:) initializer. Do not alter confstr/fcntl return, ownership, mode,
symlink or identity checks. Check existing pure launch-guard/resource regressions;
no application, helper or CLI is launched locally.

Remove await only from five synchronous NSNumber conversion calls; keep parsing
and all conversion assertions. Make the unmutated encoding document a let.
Use selectors for the actual EditorTextView undo/redo methods, preserving the
colon-taking responder-chain actions and every edit/undo/model assertion.

Gutter tests must unwrap actual optional baselines with throwing requirements,
without try?-swallowed failures or zero-value substitutes. Retain native fragment
counts, tolerance, positive-ascent, line-height and font-size comparisons. The
optional directory-use lifetime must retain exactly one optional owner and an
explicit nonnil requirement before use; clearing it must still release ownership.
Observe the expired export lease with the existing weak-lease holder, without
adding a new strong owner or changing registry assertions.

## Verification and remaining gates

Run inspected Foundation-only launch/path/value/resource tests locally where
permitted. Compile all actual package/app/UI bundles without execution. Strict
lint/pinned format, ordinary compliance, unchanged24pins/notices/SBOM and hosted
native package/app checks precede merge. Keep this change separate from PR93 and
do not integrate it before the production math candidate is qualified. Compiler
SDK/module-map messages outside these owned call sites are not claimed fixed.

## Lint reconciliation

Use fully qualified Unicode.UTF8 for the bounded byte-array decoding. SwiftLint0.65.1misclassifies the unqualified initializer syntactically as a Data conversion; both original errors are retained. A failable decoder/empty fallback would change invalid-UTF8 behavior and is not used. Existing guard tests and50000buffer comparisons pass again, and complete strict lint/format now pass1442files.
