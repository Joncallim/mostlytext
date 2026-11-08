# Preserve PDF layout while fitting the export canvas to paper

## Owner summary

Short PDF exports must not acquire an extra blank page from an oversized initial
canvas. They must also keep the same text width and wrapping near a page boundary,
and retain pages required by authored spacing. The adapter now derives its canvas
height from the actual printable paper area and removes PDF canvas scrollbar
chrome before the final HTML is validated. It keeps the established content width.

This is a bounded PDF layout correction. The existing print progress panel,
cancellation checkpoints, resource admission, output validation and atomic
publication stay authoritative. Complete ordinary menu/save-panel acceptance,
the technical-document visual corpus, final budgets and the signed release
remain separate gates. The correction introduces no new public API or dependency.

## Baseline and final ownership

The implementation starts from main `f12d6d357a2a67087db7022060fae798733d3ce7`.
That baseline already integrates the exact original-PDF readback and canvas
comparison. Final production source is
`fd23e3e264e9f34dd093151bb0f5474b0466f8c7`; its tested synthetic checkout is
`c8ddad4ecc7ded70e9b0990d30314466b51833a3`, with parents baseline plus source.
The exact computed source/tested tree is
`dcf7296128f81fd0c1b3f74315bad1f47636083c`.

The app owns paper geometry and PDF printing. ExportService owns the fixed PDF
stylesheet and composes it before final HTML validation. The validated-SVG audit
uses that same destination-specific stylesheet. HTML exports and default
stylesheet callers retain their previous CSS. No Preview activation, project
specification, package manifest, dependency pin, font or publication authority
changes accompany this correction.

## User journeys and data flow

1. Prepare an ordinary or validated-SVG PDF with the fixed PDF canvas rule in its
   stylesheet. The SVG path checks the complete owned stylesheet and final HTML;
   the adapter consumes exactly the accepted UTF-8 bytes and original destination.
2. Create one configured print-info object and both existing owned scratch URLs.
   Derive the initial view size before loading HTML, then pass that same geometry
   to the actual WebKit print operation and reapply it to the returned operation.
3. Keep the existing print/fallback validation and bounded pagination. Publish
   validated immutable bytes through the existing destination admission. Remove
   both owned scratch files on every exit path.
4. A short fixture produces one page. A boundary fixture with a 700-pixel authored
   block still requires two pages. No page is removed merely because it is blank.

## Geometry contract

`PDFSnapshotFallback.viewportSize(for:)` requires finite paper dimensions and
margins, then computes positive printable width and height. The arithmetic
helper returns width 794 and `floor(printableHeight * 794 / printableWidth)` only
when that height is finite and within 1...16384. Invalid, zero, negative,
nonfinite, overflowing or sub-pixel geometry refuses through the existing
print-configuration error. There is no default-paper substitution, clamping,
authored-content trimming or resize after loading.

## Destination-specific trusted CSS

`PDFCanvasStylesheet.css` contains exactly:

```css
html { scrollbar-width: none !important; }
```

`ExportComposer.structuralStylesheet(for:)` appends it only for PDF. Complete
stylesheet composition and companion-reference certification use the actual
trusted destination sheet. `AuditedHeadCSS.builtIn(for:target:)` uses that same
sheet and complete-byte review before minting its authority. No accepted HTML
is rewritten afterward; arbitrary authored styles cannot manufacture a receipt.

The existing closure guard recognizes exactly these reviewed SHA256 values:

| Owned bytes | SHA256 |
|---|---|
| Unchanged structural sheet | `668c19314146a74355da813dee3df584c964788e5a5b81f7233884c82ec5c5c3` |
| That sheet, newline, fixed PDF rule | `63cb41eb285e77546cfc2ed7ca0914e86f1421941563be7dc4400ef7c1709ad5` |

The extra rule contains no resource reference. Empty, unknown, URL-bearing and
single-byte-changed sheets remain rejected. Future changes to either owned sheet
still require explicit review. There is no generic CSS stripping or unconditional
trust. [WebKit's documented support](https://webkit.org/blog/16301/webkit-features-in-safari-18-2/) is a reference; the native observations below
establish the behavior of the actual qualified implementation.

## Security, lifetime and resource invariants

The existing ephemeral WebKit store, disabled authored JavaScript, restrictive
Content Security Policy, navigation refusal, 30-second load/capture limits,
256-page fallback ceiling and 256-MiB output bound remain. Existing lease checks,
cancellation, destination/source protection, complete-output validation and
atomic publication are unchanged. AppKit's existing progress panel stays enabled.
No new user-facing copy or localization key is introduced.

The native comparison runs only on a guarded disposable macOS 26 ARM runner.
It activates no product app and uses a prohibited-activation NSApplication only
for its fixed WebKit mechanism controls. Local work is source inspection, syntax
and SDK typechecking only, pure guards and read-only downloaded artifact checks;
no local app, package, font, WebKit or renderer runtime is used.

## Regression and adversarial evidence

The original nine PDF test names and assertions remain. The two real print tests
are still disabled in ordinary runs and enabled only by the bounded hosted PDF
qualification flag. Existing configuration checks add square/portrait/landscape
and invalid geometry; real short replacement adds one-page and retained-text
checks. Long-document, selectable text, heading-cut and vector controls remain.

A package integration test prepares both HTML and PDF through the actual
validated-SVG path, requires admitted SVG in each, checks PDF-only policy and
preserves exact target binding. The existing app consumer test requires exact
accepted UTF-8 bytes, SVG, policy and destination refusal. The existing closure
guard test accepts both exact owned sheets and rejects changed variants.

The native mechanism gate compiles the actual production viewport and stylesheet.
It retains seven original/candidate controls and rejects narrowed width, changed
reference text or PNG bytes, an extra short-document page, or lost authored-space
pages. The corrected short page matches the original first page image exactly;
both corrected boundary page images and raw text match their original references.
Five pure hostile-result controls include the actual observed 777-point failure.

[The qualified evidence packet](evidence/paper-canvas-qualified-firsts-2026-11-08/README.md)
records all seven complete first passes, exact original metadata/native outputs,
independent readers and actual integration proof. Actual main is
c18c5ced1397e65c2451b647b9d1dab2b6937242; its parents and tree match the qualified
source/tested/computed values above. No earlier receipt is retargeted.

| Complete first workflow | Observed result |
|---|---|
| [CI 42440443061](https://github.com/Joncallim/mostlytext/actions/runs/42440443061) |3,721 package / 537 suites; 680 app / 143 suites; original builds/lint/final pins pass |
| [PDF 42440443112](https://github.com/Joncallim/mostlytext/actions/runs/42440443112) |9 original functions, zero skips/expected failures/failures; owned 25.397 seconds, exit 0, no forced cleanup |
| [Canvas 42440443155](https://github.com/Joncallim/mostlytext/actions/runs/42440443155) |7 actual controls, 56 source bindings, downloaded helper and every output verified |
| [CLI 42440443176](https://github.com/Joncallim/mostlytext/actions/runs/42440443176) |6 comparisons, 3 actual peers, 6 kernel controls, 2 genuine normal Quits |
| [Shared 42440443292](https://github.com/Joncallim/mostlytext/actions/runs/42440443292) |29 app tests / 9 suites, both Debug and Release |
| [Heading 42440443036](https://github.com/Joncallim/mostlytext/actions/runs/42440443036) |68 controls / 9 suites, both configurations |
| [Compliance 42440443046](https://github.com/Joncallim/mostlytext/actions/runs/42440443046) |Pass |

The formerly failing package SVG/PDF integration, both exact owned-sheet checks
and app accepted-UTF8/SVG/destination checks execute and pass unchanged. Full CI's
archive uses aggregated whole-job logs instead of per-step members; independent
readback verifies the same distinct actual package/app summaries and function
pass events. No test outcome or acceptance predicate changes for that log layout.

## Decision history and preserved failures

The original 794-by-1123 canvas reproduces the two failed ordinary-export page
images exactly: 3,692 ink pixels followed by zero. The minimal-height alternative
narrows layout and changes pixels, so it was rejected.

The first paper-height candidate `3c23e399` passed all six workflow firsts. A
subsequent native boundary review nevertheless found a real 17-point content
narrowing, from 794 to 777, and changed typography. Its complete outcomes and
boundary failure remain preserved. A seven-case static-CSS prototype restored
the original short and boundary images and text, while retaining authored pages.

Candidate `932d5ca6` passed six companions and genuinely failed full CI's new
SVG/PDF integration check: 3,721 package tests, one issue, app CI not run. The
old closure guard recognized only the original stylesheet digest and correctly
refused the new owned PDF sheet. All seven complete firsts were retained before
the explicit two-owned-sheet review correction. The integration test that found
the failure is unchanged in final source `fd23e3e2`.

The original PDFKit raw canary ordering and ordinary-menu validator remain a
separate issue. Character placement observations do not constitute a replacement
oracle. The historical print-versus-fallback branch is not independently observed.
Short native adapter fixture PDF bytes are removed by the existing test cleanup;
its page/text result comes from executed assertions. The separate mechanism PDFs
and PNGs are actually downloaded and independently verified.

GitGuardian's neutral incident 39791096 concerns two occurrences of the same
public POSIX runner fixture, with no credential. Its external incident is not
marked resolved; no exemption or history rewrite is used. Source review is a
scoped orthogonal self-review, not external independent release review.

## Remaining gates and completion boundary

Update MostlyText #11 with the verified integration and precise layout remedy.
Keep whole parity, ordinary menu/save-panel/normal Quit, technical-content visual
inspection, final resource calibration, complete-operation cancellation bounds,
localization/VoiceOver and exact signed-artifact acceptance in their owning rows.
No broader issue closes from this scoped correction alone.
