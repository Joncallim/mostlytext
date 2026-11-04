# MostlyText installation, CLI and migration

MostlyText is currently a **source-only testing alpha** for macOS 26 or later.
This repository has no qualified signed and notarized 1.0 installer or production
update channel. A successful build does not verify a clean installation,
preservation of existing state, accessibility or release readiness. See
[the acceptance record](../planning/ACCEPTANCE_STATUS.md) and
[open engineering issues](https://github.com/Joncallim/mostlytext/issues) for the
current requirements and results.

## Build and use the command-line interface

Follow the locked application and CLI build commands in the [root README](../README.md#build-the-application-and-cli).
The application scheme is `MacDown2`; the CLI scheme is `MostlyTextCLI` and
produces `mostlytext`. The product is MostlyText.

The public command is `mostlytext`. Inside the app bundle, its copy is named
`Contents/MacOS/mostlytext-cli`. Keep the app bundle intact: copying the executable
alone loses the application identity and resources it needs. If you use a command
symlink, it must continue to point to that embedded executable. Do not
unintentionally replace a different installed command.

These examples describe the interface; they do not establish native acceptance.
Set `APP_BUNDLE` to the app you built or were explicitly given for testing. The
first three commands print help, version and format information without opening
documents:

```sh
APP_BUNDLE="/path/to/your/built/MacDown2.app"
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" --help
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" --version
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" formats
```

The following commands open documents and may start the app. On the development
machine, use the protected verification inputs and separate test account described
in [release hardening](../planning/RELEASE_HARDENING.md). This guide does not
authorize launching the app against the owner's profile. Starting the app through
the CLI requires a valid Apple-trusted app signature matching the embedded
command's developer team; unsigned or ad-hoc builds cannot be started this way.

```sh
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" open notes.md
printf '# Draft\n' | "$APP_BUNDLE/Contents/MacOS/mostlytext-cli" -
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" --wait notes.md
"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" open -- ./-draft.md
```

`open` is the default subcommand. `-` reads one UTF-8 stdin stream; piping input
without file arguments also selects stdin. `--wait` waits for opened documents to
close. `--` separates option-like paths from flags. `--version` must be used alone.
`formats` lists registered formats and declared preview capability; it is not a
claim that every format has completed native acceptance. The public command name
is `mostlytext`; no temporary `macdown2` alias is promised.

## Moving from a development build

Before an authorized migration test, quit the development application and back
up the existing installation and its preferences. Use the same protected inputs
and separate test account required above.

Before creating its normal stores, MostlyText inspects the development state in
`Application Support/MacDown 2` and the development preference domains. It copies
and verifies that state for the MostlyText installation and keeps an independent
snapshot of the source. The original development tree is neither moved nor
deleted. The preserved state includes settings, session and recovery records,
custom themes, snippets and user commands. Migration does not run retained scripts.

The managed installation root is `~/Library/Application Support/MostlyText`.
The transaction's published generation is `installation-v1`: its `State` directory
is the working copy and its `Source` directory preserves the captured development
files. Do not manually rename these directories, remove transaction records, edit
recovery epochs or copy preference files over a running app. They participate in
restart-safe verification. The app supplies a review location when preserved
state needs attention.

If a MostlyText profile already exists, it is kept as a whole profile. Development
preferences are not silently merged into it. Unknown or future data formats,
unsafe links or permissions, and conflicting changes stop automatic adoption
while retaining evidence.

If startup shows **Installation Needs Review**, keep the original and preserved
copies and close any other program that is writing to them. Use **Show Preserved
Installation** if it is available. After addressing the conflict, choose **Retry
Migration**, or choose **Quit**. A retry does not authorize overwriting a later
edit. When requesting help, include the message and build identity; do not
publish private documents or preference contents.

Recent-file and folder bookmarks may require selecting the location again under
the new application identity. A remembered path is not a new access grant. The
optional **original MacDown preferences** importer is a separate, deliberate
selection step after required development-state preservation; its MacDown label
names the source application. No old updater feed/key/channel is adopted.

These policies are implemented in the source. They have not yet been verified
through a complete migration of a real installed profile.
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
