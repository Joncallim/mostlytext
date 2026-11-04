# MostlyText application and CLI

This directory contains the native macOS 26+ MostlyText application, the embedded
`mostlytext` command and the `MacDownKit` package. It continues the MacDown lineage.
`MacDown2` and `MacDownKit` remain internal source/target names; the product is
MostlyText. Current status is a source-only testing alpha, with native and signed
release acceptance still open.

Use the [root README's locked build commands](../README.md#build-the-application-and-cli)
for the app and `MostlyTextCLI` schemes. Requirements are macOS 26+, Xcode 26 with
Swift 6.2+, and XcodeGen. Run the pin script after generating the project and use
Xcode's resolved-file enforcement; an unconstrained build can change dependencies.

See the [installation, CLI and migration guide](../docs/INSTALLATION_AND_MIGRATION.md)
for state-preservation behavior and release prerequisites, and the
[architecture plan](../planning/MIGRATION_PLAN.md) for module ownership. Native
app/UI testing on the development machine retains its protected test-account gate.
