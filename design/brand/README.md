# MostlyText brand assets

The public identity is frozen for 1.0 under D-031. Use **MostlyText** casing and
the **10° Slant** construction from D-027/D-029. Earlier 12° boards and validation
comparisons are history; do not take production geometry from them.

| Asset | Canonical source | Usage |
|---|---|---|
| General mark | slant/validation/slant-master.svg | Above 40 px; original geometry |
| Small mark | slant/validation/slant-32.svg | 18–40 px, derived from the master |
| Microglyphs | slant/validation/slant-16.svg and slant-icon-16-inner.svg | At most 17 px; never enlarge |
| Outlined wordmark/lockup | slant/production/out/mostlytext-wordmark.svg and mostlytext-lockup.svg | Approved Inter Tight outlines, 10° total slant; no font binary needed |
| Production geometry | slant/production/geometry.json | Generator input; see its README for exact optical corrections/rebuild |
| macOS app icon | ../../MacDown2/MacDown2/AppIcon.icon | Byte-identical integration of D-028's MostlyText-lean10.icon; native acceptance is separate |
| Markdown document icon | document-icon/build.py and ../../MacDown2/MacDown2/MarkdownDocument.icns | Owner-approved Slant-on-sheet composition; reproducible app resource and Markdown plist wiring are integrated, while installed Finder/Open With acceptance remains open |
| Repository preview | social/mostlytext-repository-preview.svg and .jpg | Opaque repository-sharing canvas built from the existing lockup; not a new logo variant |

[Provenance](PROVENANCE.md) records the original mark and outlined wordmark's
sources. Existing attribution and the application MIT license remain intact;
website licensing remains in mostlytext-site. No font binaries are redistributed.

The canonical Figma file is
[MostlyText — Brand Identity (Slant 10°)](https://www.figma.com/design/x5wTgOFnR9GgNFfUqWwKmX).
Its title was corrected through the visible file-name control on 3 November 2026;
canvas geometry and historical validation comparisons were unchanged.

Rebuild the repository preview with `python3 design/brand/social/build-preview.py`.
Its SVG has no remote/font/image dependencies; render that SVG at 1280×640 with a
browser at device scale 1 to produce the JPEG. Keep an opaque white canvas and
#11141A ink, without distorting the lockup or enlarging a microglyph. GitHub
[recommends this size and a file below 1 MB](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).
Tracking an image and installing it in repository settings are distinct steps.
On 4 November 2026 the owner explicitly approved the upload to
`Joncallim/mostlytext`. The image was installed through repository settings and
remained after reloading. An anonymous public-page readback showed the same
[repository preview image](https://repository-images.githubusercontent.com/1443787935/f144dd9d-e438-4bc1-9796-fd8bd7a84f11)
in Open Graph metadata. MostlyText #16 now records installation and fresh public
branding as checked, with the local persisted-settings screenshot and anonymous
readback retained under `CORTANA-Builds/visible-brand-20261104`. This supersedes
the 3 November failed-upload/locked-chooser status; that earlier attempt did not
establish installation.

This asset handoff completes source availability and naming. The
[document-icon build and verification guide](document-icon/README.md) records
its approved composition and reproducible source checks. It does not accept
fresh Dock/Finder appearances, installed document-icon presentation, Quick Look,
screenshot coverage, accessibility or a signed release. Gates 3 and 4 remain
waived/deferred as D-031 records, with no legal-clearance claim. See the
[identity handoff](../../planning/IDENTITY.md).
