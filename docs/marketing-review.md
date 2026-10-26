# Phase 1 article review — 26 October 2026

## Review scope

The article at `/blog/rebuilding-macdown-native-mac-app/` follows one workflow:
keep a Markdown file, compare its source and preview, then edit a Mermaid
diagram in that document. It asks for source-alpha testers and specific feedback.
PR #3 remains a draft for editorial review. No deployment is part of this work.

The article is complete with still images. Adding a video is a separate follow-up,
not a prerequisite for reviewing or publishing the text and screenshots.

## Product claims checked against the current app

The source audit used `Joncallim/macdown_2` master at
[`55564599ab9f40156f7f40c8acbe84d2acb4df7a`](https://github.com/Joncallim/macdown_2/commit/55564599ab9f40156f7f40c8acbe84d2acb4df7a).
The public alpha remains `v0.1.0-alpha.1`, source commit
`268bee5f588dc8c8a19eb3b7009040f8c182585a`; screenshots are from the separately
identified private development build. Source inspection establishes implemented
paths; the older recording establishes the depicted UI behaviour. This task did
not build or execute the current app or rerun its test suites.

Paths below are relative to the app repository at the audited commit;
`Sources/` abbreviates `MacDown2/Packages/MacDownKit/Sources/`.

| Claim retained | Evidence and limit |
| --- | --- |
| Open source, MIT, fork and successor of MacDown; attribution to Tzu-ping Chung and contributors | `LICENSE` explicitly states the lineage and preserves the original copyright. |
| Swift app for macOS 26; still named MacDown 2 | `MacDown2/project.yml`: Swift configuration, deployment target 26.0, `CFBundleName` and `CFBundleDisplayName`. |
| Documents remain ordinary Markdown files | `MacDown2/Packages/MacDownKit/Sources/FileCore/FileStore.swift` and format registry; the recording shows authored Markdown source. No claim of lossless operation for every file or guaranteed recovery. |
| AppKit text view, TextKit 2 | `MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorView.swift` wraps the TextKit 2-backed `NSTextView`. |
| Tree-sitter highlighting | `MacDown2/Packages/MacDownKit/Package.swift` and `Sources/Highlighting/`. Correctness and responsiveness are expressly qualified below. |
| Native Markdown prose preview using SwiftUI and Textual | `MacDown2/Packages/MacDownKit/Sources/Preview/TextualMarkdownPreview.swift`. Applies to prose, not every embedded renderer. |
| Click a heading to navigate | `Sources/OutlineUI/OutlineController.swift`, `Sources/Preview/ScrollSyncController+Jump.swift` and `MacDown2/MacDown2UITests/OutlineNavigationUITests.swift`; observed in the recording at 93.5 seconds. |
| Editing a Mermaid fence redraws the diagram | `MacDown2/MacDown2/MermaidDiagramBlockView.swift`, `Sources/Diagrams/` and `Sources/DiagramRendering/`; observed at 88.4–89.0 seconds in the recording. |
| Mermaid uses bundled scripts and offscreen WebKit locally | `Sources/DiagramRendering/MermaidWebRenderer.swift` and `MermaidHarnessPage.swift`; the harness limits navigation to bundled resources and blocks network connections. No app-wide “nothing is sent anywhere” or “no WebKit” claim. |
| Source-only alpha; no prebuilt download, unsigned local build, no automatic updates | [Published alpha release notes](https://github.com/Joncallim/macdown_2/releases/tag/v0.1.0-alpha.1), read live. Requirements: macOS 26+, Xcode 26, XcodeGen; build commands verified on Apple Silicon. This does not assert Intel support or a fresh full test pass. |
| Larger-file responsiveness and highlighting correctness remain open | [#203](https://github.com/Joncallim/macdown_2/issues/203) and [#459](https://github.com/Joncallim/macdown_2/issues/459), both open when checked. No benchmark or superiority claim. |
| The feedback form asks for build/environment, observed and expected behaviour | `.github/ISSUE_TEMPLATE/alpha-feedback.yml`, added on current master by #511. The article links directly to that template; signed-out readers are sent to GitHub sign-in with the return URL preserved. |

The old feature catalogue, roadmap predictions, rename/migration narrative,
WaveDrom aside and “same renderer as the preview” export claim were removed.
The sample document visible inside the first still mentions local equations and
HTML/PDF export: those are implemented (`Sources/Math*`, `ExportCoordinator.swift`,
`PDFExportAdapter.swift`), but this still does not demonstrate their correctness.
The article makes no equation/export acceptance claim.

## Real screenshot provenance

Source: `mostlytext-phase1-kit/Screen Recording 2026-10-25 at 10.37.33.mov` from
the owner's Google Drive kit. The prior review identifies it as private build
`9f360cfa24cb31c2acdf84e6e1b96732d76610dc`, still named MacDown 2.
Every figure repeats that disclosure and distinguishes it from the alpha.

Images are direct frame extractions and rectangular crops, encoded as lossless
WebP. No application content was retouched or generated. The crops omit the
test-document tabs and the defective maths preview. The original video is not
committed to the website repository.

| Asset in `public/images/blog/` | Recording frame and crop (`width:height:x:y`) | Purpose |
| --- | --- | --- |
| `markdown-source-preview.webp` | 85.0 s; `1930:680:570:320` | Source and rendered headings/lists together. |
| `markdown-preview-phone.webp` | 85.0 s; `900:680:1560:320` | The same preview at phone widths, so text is larger; the image link still opens the full source/preview comparison. |
| `mermaid-preview.webp` | 90.0 s; `900:290:1560:885` | Settled Draft → Preview → Export diagram after the edit. |

Images have descriptive alt text, intrinsic dimensions and full-size links.
The lower diagram is lazy-loaded; the initial figure is not. The three files
total 141,602 bytes (about 138 KiB).

## Corrected-video follow-up (independent of this article)

- Do not embed the current `brag.mp4`: its approximately 9–14 second window shot
  still exposes the old inline-maths glitch. Replace that shot after recording
  the fix, then review the complete export and listen to its audio.
- If a clip is added later, keep the private-development-build disclosure
  visible throughout, retain the app's actual MacDown 2 name, and name the exact
  new commit used. Do not relabel it as the public alpha or a signed release.
- Wording should say native **Markdown** preview. Diagrams use WebKit.
- Check the final music/SFX rights and credits for that exact video before
  promotion; they are not dependencies of this text-and-stills article.

## Website validation

- `npm test`: Markdown/demo tests and all 189 route/head-script assertions pass.
- `npm run build`: client, server and 20 prerendered pages generated, including
  the article and sitemap entry. `npx tsc --noEmit` passes.
- Browser review at 320, 390, 768 and 1440 CSS pixels: no horizontal page or
  article-element overflow; both figures decode, the phone crop is selected
  below 40rem, and full-size image links work. Screenshots reviewed on phone
  and desktop. Mobile menu, hash-route alias and no-JavaScript reading also
  checked before handoff.
- All article/navigation links checked against the local production preview
  and public destinations; release, issue and repository pages respond, and
  the alpha-feedback link preserves the selected form through sign-in.
  Home navigation anchors exist. The future production canonical article URL
  is currently 404, as expected before this draft is merged and deployed.
- Browser console: no errors or warnings during the checked flows.

## Release follow action and analytics

The existing release-follow route remains GitHub **Watch → Custom → Releases**.
The footer's existing Cloudflare Web Analytics disclosure is retained from the
PR. No beacon, Worker setting, DNS record, analytics configuration or credential
was added or changed by this work; the Cloudflare account configuration was not
independently re-audited here.
