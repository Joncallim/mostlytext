# Markdown document icon decision packet

## Owner summary

MostlyText identifies itself in the app icon, but Markdown files still have no
MostlyText-specific document icon. The app already declares Markdown as a public
format it can edit, at `LSHandlerRank: Default`. Adding a final icon requires a
new visual composition, even if every logo path comes from the frozen 10° Slant
artwork. Choose and review that composition before wiring it into Finder.

This packet is a design and implementation proposal, not approved artwork or
native Finder acceptance. It is based on `main` at
`892241384112a05d397a8ce292f0467e02d3ebab` (9 November 2026).

## Current source and contract

- `MacDown2/project.yml` declares `net.daringfireball.markdown`, the five
  current Markdown extensions, `CFBundleTypeRole: Editor`, and
  `LSHandlerRank: Default`. It has no `CFBundleTypeIconFile` for that type.
- `planning/IDENTITY.md` reserves the resource stem `MarkdownDocument` and
  assigns artwork, key wiring, and actual Finder/Open With presentation to #7.
- `MacDown2/MacDown2/AppIcon.icon` is the D-028 app icon. Its approved use is
  the app icon, not a document icon.
- `design/brand/README.md` supplies the 10° mark at three size ranges and
  the outlined wordmark, but no sheet, fold, badge, placement, colour or
  document-icon composition. D-031 freezes the brand geometry; D-016 forbids
  parallel stripes or a red-and-blue scheme.
- #16's document-icon and Finder/Open With rows, and #7's clean-install
  Open With/Quick Look registration row, remain unchecked.

## Proposed visual decision

Approve a simple neutral document sheet bearing the existing Slant mark in
`#11141A`, with no new monogram, text, stripes or app-icon glass background.
Use `slant-master.svg` above 40 px, `slant-32.svg` at 18–40 px, and
`slant-16.svg` at 17 px and below. Preserve each source's aspect
ratio and path exactly. A white/off-white paper silhouette, fold, border,
shadow, mark placement and any dark-mode treatment still need visual approval;
those are new artwork choices, not consequences of D-029/D-031. Review actual
16, 32, 128 and 512 px exports together before declaring this final.

Do not use `AppIcon.icns` as the document icon: it is an app tile and does not
communicate the document identity the issue asks for. Do not add a private
MostlyText Markdown UTI or change the existing public Markdown handler rank.

## Implementation after visual approval

1. Commit the approved vector source and a deterministic renderer that imports
   only canonical Slant paths. Export all `.iconset` sizes, including 1×/2×
   small sizes, then build `MarkdownDocument.icns` with `iconutil`.
2. Add the `.icns` resource to the app target and set only the Markdown
   document declaration's `CFBundleTypeIconFile: MarkdownDocument` in
   `MacDown2/project.yml`. Regenerate the Xcode project; never edit the
   generated project by hand.
3. Test byte-for-byte reproducibility of the generated `.icns`; assert the
   source paths equal the canonical mark paths, the compiled bundle contains
   `Contents/Resources/MarkdownDocument.icns`, the built `Info.plist` points
   to it, and the Markdown UTI/role/rank/extension declarations are unchanged.
   Run the repository's locked Release build and relevant checks.
4. On the disposable macOS 26 test desktop, install the exact built app in a
   clean registration state and inspect Markdown files in Finder icon/list
   views at 16/32/128 px, light and dark appearance, and Open With/Get Info.
   Record which default-handler setting Finder used; a `Default` rank does
   not make MostlyText the system owner of public Markdown. Capture the
   installed bundle identity and the actual displayed file icon. This is
   separate from source and compile-only verification.

Only after the visual decision, source implementation, built-resource checks
and genuine installed Finder readback should #16's document-icon/Finder rows
or #7's corresponding registration criterion be considered for closure.
