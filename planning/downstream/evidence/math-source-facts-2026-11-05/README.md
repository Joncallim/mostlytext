# Exact parser-owned source facts — 5 November 2026

The actual MarkdownEngine production source and all its tests run in an isolated
Foundation/C/CryptoKit-only package with the same three existing locked remote
pins: Markdown0.8.0, cmark0.8.0 and Yams6.2.2. No AppKit, SwiftUI, WebKit, product
CLI, document data or signing key executes. Every production/fixture Swift file
is byte-identical; manifest.json records exact input digests and all raw-log
sizes/SHA256. The fixture manifest and exact three-pin lock are retained.

All156 functions/22 suites pass Debug and Release. Twelve new functions cover
original UTF-8/UTF-16/scalar coordinate resolution, CRLF/CR/LF, Unicode and front
matter, tabs, nested list/quote prefixes and original newlines, precise table
cells, literal code/images/HTML, resolved link targets/titles plus raw full/
collapsed/shortcut reference keys and bracket-code boundaries. Existing parser
queue ownership/cancellation, depth, source fingerprints, YAML, block repairs
and timing controls also pass unchanged. Component Debug1MB1.219s/10MB11.126s;
Release1MB0.345s/10MB3.242s under concurrent fixture tests; not editor keystroke
or final Release acceptance. Inventory,316 Compliance and full pinned format/
strict lint pass. All24 app pins and the app manifest remain unchanged.

The first new table test fails because the actual upstream parser loses BOTH
paragraph/Text source ranges and places table header nodes at impossible columns
on the previous line when a paragraph directly precedes a table. Preserve that
failed log, initial assertion and raw AST. The projection fails closed with nil
facts for that source; ordinary separate table cells pass. This is a newly
identified production-activation prerequisite, not a fixed parser bug. It must
receive a qualified owner correction before shared math consumers activate.
Initial lint failures were corrected with named records, bounded helper functions
and normal collection syntax; no lint rule or assertion is suppressed.

ParseEngine remains the only Markdown importer. Existing Foundation worker/YAML
scalar helpers move unchanged to a Foundation-only extension to keep the importer
small. Facts are immutable and bound to the same complete-source SHA256. No AST
or second parse is exported. Existing production Math/Preview/Export remain
unchanged. This unit cannot close issue9's shared production grammar/parity,
source navigation, accessible rendering or native visual gates.
