# Preserve rendered HTML accessibility identity through its native host

## Owner summary and current repository

Rendered HTML should remain a named, navigable accessibility container when its
native web view is replaced. In frozen Preview sourcefc29 the real original UI
case fails because htmlRenderedPane is absent although the actual accessibility
hierarchy contains a rendered Hello heading and selected Rendered radio button.
Use a SwiftUI accessibility container that retains its native descendants. Do
not change the test to search for a different element or add waiting time.

Actual qualified main is56725f941f3ee8f23b6255432c229226eff8e63f. This preparation
branch contains that actual main and fc29's unmerged Preview activation. Main
still uses the previous direct WKWebView representable; the activation wraps the
replaceable WKWebView in an ordinary NSView. The failure is original38 first run
42376206030, B08case02,37PASS/1FAIL overall. Original5second assertion and compiled
source/pins/raw outcome are retained. The exported failure hierarchy has Hello,
Rendered1 and no htmlRenderedPane. This proves missing identity, not a failure
to render the page or a sole AppKit/SwiftUI implementation cause.

## Journeys, invariants and ownership

Open saved HTML in split layout: the rendered container exposes its existing
htmlRenderedPane identity and preserves WebKit headings/text as descendants.
Choose Source: the existing read-only source identity appears. The mode picker,
layout, resource notice and keyboard interactions retain their behaviour.

Only HTMLPreviewPane owns the new accessibility grouping. Insert
accessibilityElement(children:.contain) before the existing identifier on the
secured rendered host. No custom accessibility tree, combining/ignoring children,
new labels, localization strings, UI flags or testing-only product branches.
Do not change document text, native host lifecycle, navigation, cancellation,
resource authority, debouncing, CSP, JavaScript, file reads, copy or export.
Existing coordinator/main-actor/task ownership and failure behaviour remain
unchanged. No new types, interfaces, dependencies, state or concurrency paths.

## Failure model, security, budgets and interoperability

The container must disappear with rendered mode and keep descendants available.
If the unchanged original case still fails, preserve that first result before
another material change; do not assert this source-level fix worked. Existing
5second case expectations and bounded owned execution remain unchanged. No
network/file authority, new I/O, serialization or stored-data migration is added.
The change affects accessibility grouping only; authored source and exported
HTML/PDF bytes remain on their existing paths. No user-facing performance claim.

## Verification matrix and implementation slices

1. Commit this architecture and original failure identity before code. The original
   complete outcomes are also retained in the separate diagnosis final-all16packet.
2. Add the one SwiftUI container modifier. Strict lint, formatter, Swift parsing,
   immutable original UI source/manifest/controller/pin checks and compliance.
   No local AppKit/SwiftUI/WebKit runtime under CORTANA's execution hold.
3. Before publication, narrow this branch's existing manual hosted-ui-matrix
   workflow to B08 only. Its four original cases, manifest, guard/controller,
   genuine harmless positive, owned bounds and ordinary Debug build are unchanged.
   This is targeted first-result engineering, not a full38 qualification. The
   branch-local narrowed workflow must never be merged into production main.
4. Publish the exact branch and dispatch one first B08 run on the guarded disposable
   macOS26ARM runner. Verify original source/compiled test inputs, raw positive
   and four case results, real failure attachments if any and normal ownership.
5. Only after a passing targeted first result, carry the product modifier and this
   architecture into the eventual full current-main Preview remediation candidate,
   leaving the canonical ten-batch matrix unchanged. Require all full CI/Preview/
   original UI/theming and remaining activation gates before merging that candidate.

Existing B08 includes real Mermaid rendering, HTML mode switching, invalid JSON
and JSON outline paths. Keep their adversarial payloads and tests unchanged.
This unit does not waive Preview's separate initial Markdown image-copy failure,
the separate Debug50ms failure, original baseline controls or owner/final-artifact
acceptance. A targeted B08 pass alone is neither full activation nor issue closure.

## Definition of Done and stop conditions

The narrow accessibility remedy is observed only if its first real B08 case
passes unchanged with the original compiled inputs. Whole integration stays
incomplete until the complete activation candidate passes and merges. Preserve
all first outcomes and stop this remedy's readiness on any native failure,
changed security/lifecycle requirement, inaccessible descendants, required test
weakening or expanded product behaviour. No unchanged failed native rerun.
