# Shared parser evaluation and physical worker — 5 November 2026

Prepared code for the joint Preview/Export production change; adapters are not
activated by this unit. MathEvaluation retains the exact source-bound admission
and per-equation native parser body or first-party diagnostic category. Parser
locations map back through original source segments. Valid comment-only/spacing
bodies stay accepted independently of glyph geometry. Cancellation aborts partial
snapshots. User-facing localized descriptions belong to the adapter activation.

The actor owns one actual detached computation and one newest pending request.
Supersession/caller cancellation resolves only the affected submission; physical
ownership survives cancellation until work returns. Shutdown resolves active and
pending waiters and rejects new work. Private submission IDs distinguish even
repeated copies of one public request. No result can authorize live source actions
without the app's later exact-source/lifetime/generation check.

The exact inspected fixture passes **402 tests / 42 suites** in Debug (11.822 s)
and Release (3.302 s), retaining the prior 251 source/analysis and 140 parser/token
controls including 100,000 partial inputs. Added tests cover actual parser outcome
isolation, comments, empty glyph input, original LF/CRLF/CR source offsets,
resource-vs-syntax categories, cancelled preparation, a noncooperative computation
that cannot release its physical slot, pending replacement/cancellation, terminal
shutdown, independent documents and recovery after failure. Worker tests have a
one-minute failure bound and explicit owned-computation cleanup.

All 116 fixture source/test/resource files have exact SHA-256 receipts. Only the
unused outer SwiftUI Math View becomes the documented one-line namespace; no
SwiftUI, AppKit, WebKit, fonts, drawing, app, CLI, helper or signing executes here.
Engine files come from immutable 2a89c2b41482988711909572d116374e47a52164. Other
files come from this repository, including the retained prior generated comment
controls. The fixture manifest/lock retain the same Markdown/Yams owners and local
MathSyntax. Run reproduce.py with an existing engine Git repository and a new
output path, then use the printed swift test command for Debug/Release. Preparation
checks every byte before copying and does not run source code or native products.

Actual MathRenderingTests compiles locally (initial 83.49 s, final incremental
10.45 s). Full strict lint and pinned format pass 1,383 files; inventory passes
with zero unverified items. The first nesting lint failure/source remains in the
packet; flattening Outcome preserves behavior. The first packet assembly stopped
at an unlisted xcstrings resource; expanding the hash registry to the actual
resource files fixed evidence assembly without changing source/tests.

Native app compilation, production Preview/Export parity, localized diagnostics,
accessible occurrence/source actions and final Release/VoiceOver acceptance still
require their own evidence. This packet checks no whole-issue criterion by itself.
