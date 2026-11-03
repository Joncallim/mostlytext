# Export recovery catalog completion

## Owner summary

Keep the recovery storage error, recovery guidance and saved-output warning in
ExportService's normal translation catalog. Three existing unresolved-image/raw-HTML
messages also need their package bundle explicitly, so translations are looked
up alongside the catalog that owns them. This corrects string ownership without
changing export policy or claiming final localization acceptance.

Baseline: main `190d02a0f3ebc04e8d2a9250d70dc946acb27c7c`.
Owners: MostlyText #3, with #11's recovery string delta and #17 L01.

## Scope and interfaces

Only add three exact English keys with translator context to ExportService's
existing catalog and select `bundle: .module` at the three existing unresolved-image/raw-HTML
lookups. No copy changes, fabricated translations, dependencies, extraction
settings, native controls or persistence changes. Existing French/Japanese/Polish
translations and all license texts remain byte-for-byte values.

## Verification and limits

Compile the catalog; compare existing translation values; verify the three new
English values and the interpolation placeholder. Exercise the actual error
source in an owned non-application Foundation fixture using compiled package
resources, including a language override if supported. Confirm wrong-bundle
lookups do not supply those package translations. Run strict lint/pinned format,
locked compilation and full hosted CI before merge. Keep native language/layout,
VoiceOver, native-speaker review and the final string freeze open. No local
product or app-target tests may execute on the owner account.
