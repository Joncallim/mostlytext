# Markdown alias type registration

## Owner summary

MostlyText already opens `.mdown`, `.mkd` and `.mkdn` in its own format
registry, but Finder may not identify those files as Markdown. The app's
document declaration lists the extensions alongside the system Markdown type;
macOS ignores that legacy extension list when a content type is present. This
change gives the three aliases an app-owned type that conforms to the system
Markdown type and advertises them as one editable document kind. It does not
change the `.md`/`.markdown` mapping or take ownership of the system type.

## Source and platform basis

Apple's [document-type key reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)
states that `LSItemContentTypes` takes precedence over
`CFBundleTypeExtensions`. Apple's [type-declaration guide](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)
describes exported types, their conformance and filename tags, and cautions
against redeclaring a system type. MostlyText therefore keeps
`net.daringfireball.markdown` as the primary system content type and exports
`app.mostlytext.markdown-alias` only for the three otherwise unrecognized
extensions. The alias conforms to the system Markdown type, which on the
inspected macOS 26.6 host conforms to `public.data` and `public.content`.

Before this change, a Foundation `UTType(filenameExtension:)` read on that host
returned `net.daringfireball.markdown` for `md` and `markdown`, but dynamic
types for `mdown`, `mkd` and `mkdn`. This observation is host-specific and is
not proof of what an installed MostlyText build will register elsewhere.

`CFBundleDocumentTypes` now explicitly names the alias UTI alongside the
system Markdown UTI. The app's existing `Editor` role, `Default` handler rank,
five extension list and first-party format registry remain unchanged. The
duplicate human-readable description uses the existing `Markdown Document`
label; no new translated copy is claimed.

## Verification and remaining native check

The app metadata test asserts the exact system/alias relationship, alias tags,
handler role/rank and unchanged extension set. It also rejects accidental
redeclaration of the system Markdown type. The package manifest mirrors the
two declared content types. On a clean test desktop, install the final app and
check `UTType(filenameExtension:)`, Finder Kind, Open With, Get Info, document
icon and Quick Look for each of the five extensions in light and dark Finder.
Test the installed, signed candidate again before closing MostlyText #7 or
#16; source metadata and an app test do not establish Finder registration.
