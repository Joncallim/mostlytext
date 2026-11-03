# MostlyText installation, CLI and migration

MostlyText is currently a **source-only testing alpha** for macOS 26 or later.
There is no qualified signed/notarized 1.0 installer or production update channel
in this repository. A successful build does not establish clean-install,
state-preservation, accessibility or release acceptance. The current requirements
and results are tracked in [the acceptance record](../planning/ACCEPTANCE_STATUS.md)
and [open engineering issues](https://github.com/Joncallim/mostlytext/issues).

## Build and use the command-line interface

Follow the locked application and CLI build commands in the [root README](../README.md#build-the-application-and-cli).
The application scheme is `MacDown2`; the command scheme is `MostlyTextCLI` and its
executable is `mostlytext`. These internal build names do not change the product
name. The command is embedded at `Contents/MacOS/mostlytext` inside its enclosing
app. Keep that bundle intact; copying the executable alone loses its application
identity and resource context. A command symlink must continue to resolve to that
embedded executable. Do not replace a different installed command unintentionally.

The examples below describe the interface; they are not a native acceptance result.
Set `APP_BUNDLE` to the app you built or were explicitly given for testing:

```sh
APP_BUNDLE="/path/to/your/built/MacDown2.app"
"$APP_BUNDLE/Contents/MacOS/mostlytext" --help
"$APP_BUNDLE/Contents/MacOS/mostlytext" --version
"$APP_BUNDLE/Contents/MacOS/mostlytext" formats
"$APP_BUNDLE/Contents/MacOS/mostlytext" open notes.md
printf '# Draft\n' | "$APP_BUNDLE/Contents/MacOS/mostlytext" -
"$APP_BUNDLE/Contents/MacOS/mostlytext" --wait notes.md
"$APP_BUNDLE/Contents/MacOS/mostlytext" open -- ./-draft.md
```

`open` is the default subcommand. `-` reads one UTF-8 stdin stream; piping input
without file arguments also selects stdin. `--wait` waits for opened documents to
close. `--` separates option-like paths from flags. `--version` must be used alone.
`formats` lists registered formats and declared preview capability; it is not a
claim that every format has completed native acceptance. The public command name
is `mostlytext`; no temporary `macdown2` alias is promised.

## Moving from a development build

Quit the development application before starting an authorized migration test.
Preserve a backup of the existing installation and its preferences. Native tests
on the development machine use protected verification inputs and the separate test
account described in [release hardening](../planning/RELEASE_HARDENING.md); this
guide does not authorize launching the app against the owner's profile.

The implemented startup transaction inspects the legacy `Application Support/MacDown 2`
state and development preference domains before ordinary application stores are
created. It copies and verifies state into the MostlyText installation, retaining
an independent source snapshot. The original development tree is not moved or
deleted. Covered authoritative state includes settings, session/recovery records,
custom themes, snippets and user commands. Retained scripts are not run by migration.

The managed installation root is `~/Library/Application Support/MostlyText`.
The transaction's published generation is `installation-v1`: its `State` directory
is the working copy and its `Source` directory preserves the captured development
files. Do not manually rename these directories, remove transaction records, edit
recovery epochs or copy preference files over a running app. They participate in
restart-safe verification. The app supplies a review location when preserved
state needs attention.

An existing MostlyText profile wins as a whole profile; development preferences
are not silently merged into it. Unknown/future data, unsafe links or permissions,
and conflicting changes stop automatic adoption while retaining evidence. If
startup reports a conflict, retain the original and preserved copies, close any
other writer, and use the offered review/retry or quit action. A retry does not
authorize overwriting a later edit. Report the message and build identity when
requesting help; do not publish private documents or preference contents.

Recent-file and folder bookmarks may require selecting the location again under
the new application identity. A remembered path is not a new access grant. The
optional **original MacDown preferences** importer is a separate, deliberate
selection step after required development-state preservation; its MacDown label
names the source application. No old updater feed/key/channel is adopted.

These are implemented policies, not a completed real installed-state rehearsal.
[The migration contract](../planning/downstream/whole-install-migration.md) records
exact ownership, conflict and verification details. Issues [#4](https://github.com/Joncallim/mostlytext/issues/4)
and [#16](https://github.com/Joncallim/mostlytext/issues/16) retain native migration,
retry, installed CLI and update acceptance.

## Preparing a public release

Release operators follow the [two-candidate sequence](../planning/RELEASE_SEQUENCE.md)
and [Mac signing brief](../planning/MAC_SIGNING_BRIEF.md). The release script
`release/macos/sign-notarize-dmg.sh` requires an explicit mode and real Team ID and
notarization-profile configuration. `--preflight-only` checks prerequisites without
building, signing or submitting. The latest real preflight finds the Developer ID
certificate and stops because `mostlytext-notary` is absent; that is an unfinished
credential prerequisite, not a signing pass.

A private candidate first needs software/native verification; final localization
then freezes the baseline. The final signed/notarized candidate needs current
notices, SBOM, approved publicly retrievable corresponding source, installed-state
migration, Gatekeeper, CLI and a signed N-to-N+1 update rehearsal. Public promotion
requires its separate authorization and must use the same verified bytes. See
[#14](https://github.com/Joncallim/mostlytext/issues/14) for third-party rights/source
gates and [#8](https://github.com/Joncallim/mostlytext/issues/8) for the consolidated
acceptance gate. The website is maintained separately in
[mostlytext-site](https://github.com/Joncallim/mostlytext-site).
