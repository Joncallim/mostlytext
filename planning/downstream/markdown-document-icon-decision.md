# Markdown document icon decision packet

## Owner summary

MostlyText identifies itself in the app icon, but Markdown files still have no
MostlyText-specific document icon. The app already declares Markdown as a public
format it can edit, at `LSHandlerRank: Default`. Adding a final icon requires a
new visual composition, even if every logo path comes from the frozen 10° Slant
artwork. The owner approved this composition from the review sheet on
9 November 2026; installed Finder presentation is still unverified.

This packet records the approved composition and its implementation candidate,
not native Finder acceptance. It is based on `main` at
`892241384112a05d397a8ce292f0467e02d3ebab` (9 November 2026).

The isolated branch adds a **review candidate** built by
`design/brand/document-icon/build.py`, `MarkdownDocument.icns`, and the narrow
Markdown plist resource reference. These source files make the visual choice
concrete without claiming it has been accepted in Finder.

## Current source and contract

- `MacDown2/project.yml` declares `net.daringfireball.markdown`, the five
  current Markdown extensions, `CFBundleTypeRole: Editor`, and
  `LSHandlerRank: Default`. The main baseline named above had no
  `CFBundleTypeIconFile` for that type; this candidate adds the key.
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

### Separate extension-registration finding

On macOS 26.5.1, a read-only Uniform Type Identifiers lookup resolves `.md`
and `.markdown` to `net.daringfireball.markdown`, while `.mdown`, `.mkd` and
`.mkdn` resolve to dynamic types. [Apple's `CFBundleDocumentTypes` reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html#//apple_ref/doc/uid/TP40009249-SW8)
states that `CFBundleTypeExtensions` is ignored when `LSItemContentTypes` is
present. The runtime registry and source manifest support all five suffixes,
but their actual Finder/Open With registration cannot be inferred from the
five source plist strings. Test all five on a clean installed test account.
An imported-type declaration may be needed for the aliases, but [Apple advises](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)
against redeclaring a system-provided type. Resolve that registration behavior
before changing the UTI contract or checking #7's Finder criterion.

## Approved visual composition

The candidate is a simple neutral document sheet bearing the existing Slant mark in
`#11141A`, with no new monogram, text, stripes or app-icon glass background.
It uses `slant-master.svg` above 40 px, `slant-32.svg` at 18–40 px, and
`slant-16.svg` at 17 px and below, measured at the mark's displayed size.
The generator preserves each source's aspect ratio and path exactly. The owner
approved the review sheet showing the white/off-white paper silhouette, fold,
border, mark placement and no separate dark-mode variant on 9 November 2026.
Those choices are new artwork, not consequences of D-029/D-031. Actual Finder
appearance remains to be checked at 16, 32 and 128 px in light and dark.

Review PNGs and a vector source are under `design/brand/document-icon/preview/`.
They are generated from the same source as the `.icns`; `verify.py` compares
their bytes against a fresh rebuild.

Do not use `AppIcon.icns` as the document icon: it is an app tile and does not
communicate the document identity the issue asks for. Do not add a private
MostlyText Markdown UTI or change the existing public Markdown handler rank.

## Implementation and Finder acceptance

1. The approved candidate's standard-library generator imports only canonical
   Slant paths, renders all `.iconset` sizes through macOS `sips`, including
   1×/2× small sizes, then
   builds `MarkdownDocument.icns` with `iconutil`.
2. Keep the `.icns` resource in the app target and set only the Markdown
   document declaration's `CFBundleTypeIconFile: MarkdownDocument` in
   `MacDown2/project.yml`. Regenerate the Xcode project; never edit the
   generated project by hand.
3. Test byte-for-byte reproducibility of the generated `.icns`; review the
   generator's canonical mark input paths, and assert the compiled bundle contains
   `Contents/Resources/MarkdownDocument.icns`, the built `Info.plist` points
   to it, and the Markdown UTI/role/rank/extension declarations are unchanged.
   Run the repository's locked Release build and relevant checks. The local
   `design/brand/document-icon/verify.py` runs the source and bundle checks.
4. On the disposable macOS 26 test desktop, install the exact built app in a
   clean registration state and inspect Markdown files in Finder icon/list
   views at 16/32/128 px, light and dark appearance, and Open With/Get Info.
   Record which default-handler setting Finder used; a `Default` rank does
   not make MostlyText the system owner of public Markdown. Capture the
   installed bundle identity and the actual displayed file icon. This is
   separate from source and compile-only verification.

The visual decision and source/build checks are recorded. Keep #16's
document-icon/Finder rows and #7's registration criterion open until genuine
installed Finder readback on the exact candidate.

## Local candidate verification, 9 November 2026

- `python3 design/brand/document-icon/verify.py` passes: tracked `.icns` and
  review exports reproduce byte for byte, all ten iconset slots extract at the
  requested dimensions, and the generated source plist contains exactly the
  intended Markdown icon key.
- `xcodegen generate`, package-version pinning and the locked Release
  `xcodebuild ... -scheme MacDown2 -configuration Release build` pass. Running
  `verify.py --app` against that compiled app confirms its `Info.plist`,
  byte-identical `Contents/Resources/MarkdownDocument.icns`, and retained
  `AppIcon.icns`. The candidate `.icns` SHA-256 is
  `b36d4b9c765ed1de034ec2648cd22a0cf2c2f345465eb5105af4c32abaa44d69`.
- `python3 compliance/tools/compliance.py check` passes with the new first-party
  resource registered.

These are source and compile-only checks. The app was not launched, installed,
or registered with Finder here. The owner has approved the composition;
installed Finder/Open With acceptance remains open.
