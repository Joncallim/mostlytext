# Validated body rendering and equation actions — architecture draft

Baseline production main f362b61b759068bdcbebf79749dbfdf92a47e82a; prepared prerequisite PR87
c75d59d2db1c37c8240a0bb909573f3c4c603691 provides actual engine inspection. Do not
implement against a moving or failing prerequisite. This draft resolves the next
boundary; it is not production activation or acceptance evidence.

A validated body is an opaque immutable engine value that can only be obtained
from the actual parser's bounded body inspection. It stores original raw body
bytes and the explicit limits, never an escaping mutable atom tree. Validation
returns the same structured invalid/internal/resource outcomes as inspection,
plus a token on success. The existing inspection API remains source compatible.
The token equality/hash must compare exact UTF-8 bytes rather than Swift String
canonical equivalence. It is a renderer cache key component, not a source occurrence.

The engine adds Math.init(ValidatedBody) and typographicBounds(for:ValidatedBody,
...). Both layout and Canvas use one private render-input enum, separating legacy
auto-delimiter String input from validated raw-body input. Cache keys include that
mode and body limits, so cached automatic interpretation cannot bypass raw-body
parsing or limits. On a cold token render, rerun the actual bounded parser in body
mode (no delimiter detection). Cancelled/failed revalidation yields no glyphs and
must not publish a new valid result. Rendering is still font/UI work; bounded
parsing is not a hard graphics execution deadline. Existing legacy String API
remains usable and retains its automatic delimiter semantics.

Give AST and display caches explicit finite entry ceilings. These are safety
limits on retained entries, not a claim of exact byte accounting or whole-editor
performance. Cache misses recompute the same immutable semantics; eviction can
never discard authored source. Enforce identical mode/body/limit keys for both
primary and measured-width alias display entries. Keep font/style/proposed width
in display identity. Actual 100-equation benchmark must remain unchanged and pass.

Textual adds a backward-compatible typed attachment factory accepting the engine
ValidatedBody, the existing inline/display style and caller-owned occurrence UUID.
Only that validated overload accepts a caller-localized authored-source label and
localized action name. Existing .math(latex:...) factories/parser behavior remain
source compatible. A default-no-op environment action taking UUID allows a user
to activate the accessible equation without inventing a URL scheme. This is not
first-party source authorization: the eventual app callback must resolve the UUID
in its accepted current lifetime/generation/exact-source analysis, select its own
range, and clear secondary selections via existing E22 controls. Stale or absent
UUIDs do nothing. No authored URL can mint that UUID capability.

The attachment's SwiftUI view presents its authored label as an image/equation
and a named accessibility action. SourceAction is optional when no identity is
provided; no bogus action is exposed. Actual system VoiceOver is still a held
native criterion. Hosted native component tests must show the accessible wrapper
is built through the existing inline paragraph attachment path, preserve neighbors
(including scalar boundaries inside graphemes), sizing and source identity. Final
app accessibility tree and keyboard/source selection remain separate evidence.

No whole Markdown renderer replacement, second Export renderer, document source
rewrite, hosted service, product CLI/native local execution or signing-key use.
No first-party diagnostic string is hard-coded here: caller localizations will
enter catalogs with the joint production adapter. Font/resource/licence bytes and
unrelated third-party runtime sources remain unchanged. If the actual Textual
paragraph renderer drops the wrapper or source action, stop for a named focused
probe instead of claiming accessibility from an unattached SwiftUI value.

Qualify Foundation token semantics, exact cache mode identity and error behavior;
compile actual engine/Textual locally only; run real hosted typesetter/attachment
and full package/app/all4-build CI. Preserve original failures. Then jointly
activate Preview and Export against shared source-bound analysis, shared valid
body tokens/error semantics and physical worker budgets. Do not enable one path
while the other still strips comments/newlines or uses independent dollar grammar.

## Textual accessibility preimplementation finding

Actual Textual AttachmentView.swift resolves each attachment.body as a Canvas
symbol and draws it at Text.Layout run bounds. An accessibility label/action on
MathView alone cannot be assumed to survive that symbol rasterization. The next
slice needs a named actual hosted accessibility probe before choosing the final
presentation. Candidate options: native accessible per-occurrence overlays using
the already available run geometry, or an accessibility representation that
preserves ordinary paragraph/link reading order. Do not replace whole paragraph
accessibility or hide unrelated inline text/links. Do not claim that a labeled
Canvas symbol establishes an equation element. Native VoiceOver remains separate.

## Ready implementation boundary

The raw-body rendering slice may proceed independently of the accessibility
probe. Its immutable prerequisite interfaces are recorded in PR87 and engine
e394d7cf111a90b4393df7a18e989dfec0a28931/Textual2337a7751605ed819ed6ce71a450fe29608deb40.
Do not merge the dependent app slice before that prerequisite qualifies/merges.
This slice changes only engine validated-body/render-input/provider plumbing,
Textual's typed factory/body choice and matching dependency metadata, first-party
native component tests, and compliance/evidence. No app production adapter yet.
Accessibility factory data/actions remain excluded until the focused Canvas
probe chooses an effective representation. Keep that deferred scope explicit.

The public token has read-only source and limits and a non-public initializer;
only validateBody can produce it. BodyValidation repeats inspection outcomes,
carrying ValidatedBody only on success. validateBody performs one inspection;
rendering reparses on an AST cache miss with the same body mode and limits.
DisplayProvider uses RenderInput as the atom and display cache identity, including
both primary and measured-width alias keys. Legacy automatic input and raw body
are distinct, with exact UTF-8 hashing/equality. AST cache retains at most 512
entries; display cache at most 1,024 entries. Entry ceilings do not promise exact
resident-byte accounting or interrupt graphics operations already in progress.

Named native checks must compare typed attachment bounds with engine token
bounds; prove automatic versus raw-body cache isolation in both invocation orders;
retain authored source, comments and source UUID; cover repeated equal equations
with distinct occurrences; and keep the original real 100-equation renderer
budget unchanged. Existing String factory remains compatible. Foundation checks
exercise token factory failures, exact-byte identity and actual raw-body parser
semantics. Cache mutation remains inside the existing serial lock; no mutable AST
or display tree escapes the existing renderer boundary. Cancelled raw-body calls
must not return a cached display before observing ambient cancellation.

Completion requires exact owner patches/licence and unaffected-file hashes,
Foundation Debug/Release controls, actual target compilation, complete hosted
package/app tests and all four locked builds, verified merge and issue re-audit.
This cannot alone close shared grammar/parity, source diagnostics, accessibility,
navigation or final native acceptance. The next production unit must jointly
switch Preview and Export, including reference-link identity under rewriting.
