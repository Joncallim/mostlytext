# Owned compiler diagnostics

Base9c3d6358322a4971a9704dd08fc59f082ec64640 (PR93 candidate). The original complete
run42106201852 records17distinct owned warnings. All17are absent in the actual
complete package-test and app/UI-test compilations after this bounded correction.
No native tests execute in the owner account; these are compilation receipts.

The existing pure launch-guard suite passes5tests in Debug/Release. All real
MarkdownEngine source/tests are copied unchanged into a Foundation-only fixture;
the affected FrontMatterTests pass27tests Debug/Release. The retained comparison
program proves exact old/new output equality for50,000 NUL-terminated byte buffers,
including invalid UTF-8, embedded terminators and ignored suffixes. Its deliberate
old-API warning belongs only to the comparison program, not distributed code.

Gutter nil checks now throw at the actual missing value instead of using try? and
zero defaults; native measurement/tolerance/positive-ascent/font/line-height checks
remain. The optional resource-use owner retains one explicit nonnil requirement
and still releases by assigning nil. Undo selectors reference the actual colon-
taking EditorTextView methods, preserving responder-chain and model assertions.
The expired export lease uses the existing weak holder, adding no strong owner.
UID, confstr/fcntl return, owner/mode/symlink, source and publication guards remain.
All24pins, notices and SBOM bytes remain unchanged; ordinary compliance passes.

Hosted package/app execution remains required before merge, after PR93's own
production activation qualification. This does not close native UI/account,
release/signing, localisation or independent compliance acceptance gates.


## Corrected lint qualification

The original first-lint log contains two optional_data_string_conversion errors;
those errors were missed before opening the draft. Hosted lint on994a6f25 also
fails. This is not a complete lint pass. SwiftLint0.65.1's rule syntactically
flags String(decoding:as:UTF8.self) regardless of the actual byte-array input.
Using fully qualified Unicode.UTF8 makes the intended byte decoder explicit
without changing replacement decoding, adopting failable/empty behavior, disabling
a rule or changing confstr/fcntl and ownership checks. Exact guard source again
passes5tests Debug/Release;50000old/new buffer comparisons again match exactly.
Complete package/app/UI compilations pass with no owned warnings. Full strict
lint and pinned format now pass1442files. The new receipts/logs describe this
source; original failed logs and earlier source receipts remain preserved.
Fresh exact-head hosted checks are still required before merge.
