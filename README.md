# MostlyText

A native macOS text and Markdown editor, built with Swift, SwiftUI and TextKit 2.
MostlyText continues the MacDown lineage, with a rewritten application and a
modular Swift package core. The command-line executable is `mostlytext`.

**Status: source-only testing alpha.** Source integration and automated checks
are not native acceptance or a signed, notarized release. Remaining work includes
native editing/export/accessibility journeys, installed-state migration,
localization, performance and exact release-artifact verification.

- Website: [mostlytext.app](https://mostlytext.app)
- Website source: [Joncallim/mostlytext-site](https://github.com/Joncallim/mostlytext-site)
- Engineering backlog: [MostlyText issues](https://github.com/Joncallim/mostlytext/issues) ([old-to-new number map](planning/ISSUE_TRANSFER_MAP.md))
- [Repository migration contract](planning/downstream/mostlytext-repository-migration-2026-11-03.md)
- [Current acceptance status](planning/ACCEPTANCE_STATUS.md) and [identity handoff](planning/IDENTITY.md)
- [Historical release evidence](planning/RELEASE_EVIDENCE.md)

## Build the application and CLI

Requires macOS 26+, Xcode 26 with Swift 6.2+, and XcodeGen. Internal target/package paths and selected legacy compatibility identifiers
are retained as documented in the identity handoff; the public CLI
scheme is `MostlyTextCLI` and produces `mostlytext`.

```sh
cd MacDown2
xcodegen generate
cd ..
bash MacDown2/scripts/pin-xcode-package-versions.sh
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 \
  -configuration Release -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile build
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MostlyTextCLI \
  -configuration Release -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile build
bash MacDown2/scripts/pin-xcode-package-versions.sh --check
```

Build and test the package with its committed dependency versions:

```sh
cd MacDown2/Packages/MacDownKit
swift build --force-resolved-versions
swift test --force-resolved-versions
```

Use Release builds when judging responsiveness. Native app/UI testing must use
its protected verification inputs and the separate test account; see the
isolation scripts and [release hardening](planning/RELEASE_HARDENING.md).

## Source layout and history

`MacDown2/` contains the application, CLI, tests and packages. `planning/` records
architecture, acceptance and historical evidence; `design/` contains brand assets.
`compliance/` contains the dependency inventory, notices and source obligations.
Original MacDown source is retained under the read-only historical tag
[`macdown-original-reference-3e2a2bf1`](https://github.com/Joncallim/mostlytext/tree/macdown-original-reference-3e2a2bf1);
there is no `legacy-reference/` directory in the current tree. `website/`
is an earlier planning draft; the maintained public website has its own repository.

The full application history was imported from `Joncallim/macdown_2` at
`8be8ad4158f6fee5ad8bd40337e118054177cfa8`. The tag
`macdown-2-lineage-2026-11-03` records that boundary. Existing tags are preserved;
The 17 open engineering issues were transferred with redirects and discussions;
[their number map](planning/ISSUE_TRANSFER_MAP.md) preserves traceability. GitHub
release assets and workflow-run records remain at their original URLs. Historical alpha release files remain in the
[original repository](https://github.com/Joncallim/macdown_2/releases).

## License and attribution

MostlyText's application source remains under the [MIT License](LICENSE).
The original MacDown copyright and later contributors' attribution are retained.
Third-party components keep their own terms in [the generated notices](compliance/generated/THIRD_PARTY_NOTICES.md).
The separately maintained website has its own license; its terms are not changed
by this application migration.
