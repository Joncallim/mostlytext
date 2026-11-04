# Correct document registration and embedded CLI instructions

The current project declares Markdown's handler rank Owner although MostlyText
is an ordinary editor of public Markdown, and declares Editor as the rank for
HTML/JSON/YAML/plain text. Apple's documented ranks are Owner/Default/Alternate/
None; Editor is a document role, not a rank. Fix this source criterion in #7 and
retain real Finder/Open With acceptance separately. The guide added in #44 also
uses Contents/MacOS/mostlytext even though the actual post-build script and built
bundle embed mostlytext-cli; public command naming remains mostlytext.

Baseline: stacked on #45 source 40672198. Commit this architecture before changes.
Use Default rank for ordinary Markdown/HTML/JSON/YAML/plain-text editor claims.
Preserve Editor roles, existing Alternate source/TOML ranks, supported UTIs and
all migration-sensitive compatibility identifiers. Add no new document ownership,
artwork, Quick Look target, registry action or app execution.

Correct the standalone guide's embedded paths and explain the public command /
embedded filename distinction. Check its examples against the actual built bundle
and source argument parser; never execute the product on the owner account.
Internal MacDown2.app/executable/module paths remain as documented; their broader
coordinated packaging transition is not silently widened into this correction.

Add a small metadata verifier that checks Apple rank/role vocabulary, rejects
public Markdown Owner claims, and validates the real embedded helper/resource
paths in a compiled app. Use meaningful invalid-plist/absent-helper controls and a
failing-before generated baseline. Verify generated and compiled Info.plist,
locked compile-only Release, complete hosted CI/Compliance and source self-review.
Never change default associations or register an app on this account. Check only
the source rank and corrected documentation criteria after qualification/merge;
actual installed Open With and native migration/CLI remain required.

Primary specification:
https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html#//apple_ref/doc/uid/TP40009249-SW1
