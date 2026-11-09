# MostlyText identity handoff

This is the current public identity and identifier handoff for MostlyText #16,
Mac integration #7 and distribution #4. It records source implementation and
reserved conventions separately from native acceptance. Frozen brand decisions
D-027–D-031 remain authoritative; no new geometry or legal clearance is implied.

## Public names and destinations

| Surface | Canonical identity | Evidence/status |
|---|---|---|
| Product/display name | MostlyText | project.yml, welcome/About and catalogs |
| Application source | https://github.com/Joncallim/mostlytext, main | Complete rewrite history preserved; original MacDown history separately tagged |
| Website | https://mostlytext.app | Public product domain; source at https://github.com/Joncallim/mostlytext-site with its own license. Owner-approved identity/FAQ and public-claims corrections are deployed and publicly verified; see the [recorded website evidence](downstream/website-public-claims-2026-11-05.md) |
| GitHub sharing preview | design/brand/social/mostlytext-repository-preview.jpg | Owner-approved installation persisted and anonymous public Open Graph image verified on 4 November 2026; see the [brand registry](../design/brand/README.md) |
| Engineering backlog | https://github.com/Joncallim/mostlytext/issues | The 17 original issues transferred; see [number map](ISSUE_TRANSFER_MAP.md) |
| Historical source/releases | https://github.com/Joncallim/macdown_2 | Preserve old closed issues, PRs, alpha assets and exact-source/native evidence |
| Public command | mostlytext | MostlyTextCLI scheme; internal target/module MostlyTextCommand |
| Embedded command | Contents/MacOS/mostlytext-cli | Required helper binding, not a second public command |
| Current development version | 0.1.0 (1) | Do not label source integration as a 1.0 release |
| Release version policy | 1.0.0; independent increasing build number | Owner decision; applied/verified by #4 on the final candidate |

## Implemented runtime identities

| Identifier | Current source | Why it stays |
|---|---|---|
| Application/defaults domain | app.mostlytext.MostlyText | Canonical production identity, injected after migration readiness |
| Workspace domain | app.mostlytext.MostlyText.workspace | ApplicationStorageLocations; journaled state publication |
| Theme file type | app.mostlytext.theme | project.yml and ThemeExportDocument; conforms to public.json |
| Theme extension | .mostlytext-theme | Only its own extension is claimed; generic JSON is not owned |
| App icon source/stem | MacDown2/MacDown2/AppIcon.icon; AppIcon | Frozen D-028 document adjacent to Assets.xcassets; source integrated |
| Markdown document icon source/stem | MacDown2/MacDown2/MarkdownDocument.icns; MarkdownDocument | Owner-approved Slant-on-sheet composition and Markdown-only `CFBundleTypeIconFile` integrated in PR166; installed Finder/Open With presentation remains #7 |
| Internal app filename/executable | MacDown2.app / MacDown2 | Current build/release/CLI/test consumers depend on these paths; #4 owns coordinated packaging transition |
| Internal project/package paths | MacDown2 / MacDownKit | Build/module names, not public product branding |

Opening theme JSON as ordinary text does not install it. Installation remains an
explicit Appearance action. Naming/type source completion does not prove native
import/export panels, Finder, VoiceOver or installed-state acceptance.

## Reserved integration conventions

These are future handoff names, not claims that a target or deployed feed already
exists. They use the owner-frozen app.mostlytext. prefix and preserve the app
identifier. The implemented Markdown document icon is recorded above.

- Quick Look extension bundle identifier: app.mostlytext.MostlyText.QuickLook.
  It derives from the containing app ID. #7 must add and validate the actual
  extension, supported Markdown types, signing and native invocation. The current
  project has no Quick Look target; do not mark that implementation complete.
- Future public types/extensions follow the app.mostlytext. prefix. The current
  custom-theme type/extension above are implemented and need no further naming
  decision. No generic JSON, TOML or source-code ownership is added here.
- The owner-selected default appcast URL is https://mostlytext.app/appcast.xml.
  This is a reserved default, not a deployed feed, implemented Sparkle channel,
  verified update or signing key. #4 owns feed/key/channel and N→N+1 acceptance.

## Migration-sensitive legacy identifiers

Preserve these values until their owning migration/compatibility contract is
satisfied. Their presence is deliberate and is not an invitation to mass-rename.

- com.joncallim.MacDown2 and com.joncallim.macdown2.workspace: development
  preferences/workspace domains consumed by whole-install migration.
- Application Support/MacDown 2: development theme, command, snippet, session
  and recovery inputs. Convenience defaults in package types remain historical;
  the production app supplies transaction-selected storage locations.
- com.joncallim.macdown2.file-tree-item: internal drag-and-drop payload type.
- com.joncallim.macdown2.toml: existing document-type compatibility declaration;
  changing it requires a deliberate registry/migration and native-association pass.
- UITestIsolated bundle prefixes, lock names, frame-autosave keys, diagnostics
  subsystems and test fixture names: internal compatibility/protection identifiers.
- Original MacDown attribution, license text, archived design comparisons, dated
  architecture and exact-source evidence: historical facts, not current advertising.

For every new name, change public copy where appropriate and leave a retained
identifier explained here or in its owning architecture. #4 must prove real
profile/state preservation; no data acceptance follows from a documentation edit.

## Artwork and acceptance

Use the [brand asset registry](../design/brand/README.md), the frozen Slant mark,
outlined Inter Tight wordmark, accepted app icon source and approved Markdown
document icon source. Microglyphs are used only at their intended sizes. Legal
review/registration remains owner-deferred under D-031; it is not passed or
certified here.

The document icon uses the existing `net.daringfireball.markdown` content type;
the source manifest lists five Markdown suffixes. The
[icon decision packet](downstream/markdown-document-icon-decision.md) records
why those strings do not prove Finder registration of every alias. Native
icon/list views and Open With/Get Info remain #7 and #16 acceptance.

See [current acceptance status](ACCEPTANCE_STATUS.md) for local prerequisites and
[current signing instructions](MAC_SIGNING_BRIEF.md). Fresh native visual and
accessibility, Quick Look/Finder and installed document-icon presentation,
packaged product naming, installed migration, localization freeze, updates and
exact signed-artifact acceptance remain open in their owning issues.
