# Replay references consumed by the real parser

## Owner summary and baseline

Production math needs the same reference targets as the original whole-document
parse. Preview's existing line extractor is not fence-aware, omits multiline/lone-CR
and escaped-bracket definitions, and cannot authorize definitions from structural
facts. Replacing equation labels with markers makes that gap relevant to activation.
Do not copy URLs/titles into invented Markdown definitions or scan code for apparent
definitions. Capture the actual definitions the existing parser consumed instead.

The exact source owners are cmark 2a5339b8 and Swift Markdown abfafecc; their original
coordinate fixes remain. Main is e8201ad8. PR90 and PR91 are merged; their exact common tree
qualifies all 3,576 package and 623 app tests and all four locked builds. The additive
raw-body renderer now passes all 37 hosted component tests in run 42071107835;
production grammar and current-document action wiring are still not activated.

## C ownership and metadata

In the parser's existing successful reference-definition consumption, retain a copy
of the consumed logical definition bytes (after the parser's existing container/
line-ending handling) and its opaque reference-map creation identity. Keep record
order, including duplicates; do not synthesize destination/title spelling. Definitions
inside code/HTML never enter this path. Attribute references remain separate.

Store the owned record array only in the document node's existing union, with its
allocator and explicit free path. Store a resolved reference identity on actual
link/image nodes in their existing union. Prove sizeof(cmark_node) does not increase.
A direct/auto link has identity zero. Reference-map first-definition behavior,
expansion budgets, parsing, HTML and formatting algorithms stay unchanged. Expose
read-only borrowed getters for record count, source bytes, identity and resolved
link identity; invalid node/index returns zero/nil. No dangling use-node pointers
or side registry survives arbitrary tree edits.

## Swift boundary

Swift Markdown copies definition records and actual reference-use source ranges
before freeing the C tree, using the same final coordinate conversion as ordinary
links. Keep this optional metadata on Document values only, outside RawMarkupData;
no per-AST-node header growth, public link semantic change, second parse or global
identity registry. Programmatically constructed/modified documents have no parser
metadata. Scope the additive record/read API to the MostlyText SPI. A separate C
iterator over the final tree collects only actual reference uses; definition IDs
bind those uses to the captured record, removing label normalization guesses.

Block-directive parsing currently parses separate ordinary runs. Its synthetic
Document does not claim whole-document reference metadata. In the first-party
ParseEngine, when that opt-in structural mode is enabled, derive the source facts
and reference metadata from one ordinary whole-body CommonMark parse while keeping
the configured structural blocks/outline. Preview/Export already deliberately show
directive text as ordinary Markdown. This reconciles shared math/reference facts
with their actual consumer semantics. The extra parse is off-main in the existing
physical parse slot, only for this opt-in mode; default performance is unchanged.

## First-party selection and bounds

Wrap records as renderer-neutral MarkdownEngine facts, bound to the same exact
source SHA. Opaque IDs bind uses to raw records inside the parser SPI. First-party facts
retain the raw syntax and actual use ranges, including reference images; uses are converted through the same original UTF-8-to-UTF-16 coordinate projection, including
front matter. A block's trusted original range selects only the definitions used
by its actual original links/images. Replay those raw logical strings in original record
order, with blank-line separation, before the existing marker transport. Unknown,
foreign, generated or inline-composed blocks cannot mint source authority. Apply
the complete 64 KiB expanded-input cap before native parsing. No full-source SHA or
whole-document rescan per block. A source-bound definition index is built once per
snapshot; block selection is proportional to its own links.

## Qualification and stop conditions

First capture failures of the old line extractor for fenced fake definitions,
escaped labels, multiline destination/title, CR/LF/CRLF, quotes/lists/lazy prefixes,
Unicode byte-distinct keys and duplicate/first-definition precedence. Prove replay
retains actual target/title and own equation attributes through the real native
parser; do not accept a guessed URL serialization as equivalent evidence.

Run original C tests/spec/regressions and sanitizers, original Swift Markdown tests,
the exact first-party Foundation parser tests and original/candidate semantic/HTML/
format corpus comparison. Preserve every first failure. Check allocator lifetime,
manual/mutated document behavior, invalid getters, duplicate identities and no
per-node growth. Retain immutable source hashes, licenses and changed-file receipts;
new owner pins/inventory/notices/SBOM and complete app/CLI CI are required for adoption.
If source authority or replay target/title cannot be proved, retain readable source
and correct the owner rather than weakening transport provenance or parser limits.
This prerequisite alone closes no whole math/Export/native release criterion.

## Preserve original link and image authority after replay

A concrete actual-parser control establishes that the whole-document 100,000-byte
reference expansion allowance can be exhausted before an equation label. Replaying
the last block with a selected definition resets that budget and makes a previously
unlinked equation clickable. Keep the original parser limits unchanged. Definition
selection alone cannot authorize the resulting native attributes.

Retain source-bound resolved image ranges/destinations beside existing link facts,
while keeping images wholly excluded from equation admission. Preview input accepts
only caller-proven block-local link/image ranges with original resolved destinations.
Forward-map those endpoints through the exact existing substitutions and prefix;
reject endpoints inside edits, invalid scalar/CRLF boundaries or over-budget lists.
Store ranges and destinations without synthesizing Markdown or changing source.

Before marker restoration, inspect every actual native link/image URL attribute.
Its native parser position must resolve through the owned numeric source map and
fit wholly inside a matching original reference of the same role. Compare actual
URL bytes with Foundation URL construction from the original parser destination
and the same base URL. A foreign, changed, newly created or unpositioned attribute
fails the entire affected block to original visible plain source, including cases
with no equation markers. An omitted authority list authorizes no links/images.
No native URL may acquire capability just by equal text or a replayed definition.
This guard proves source meaning; existing URL-open/resource policy remains.

Native tests first preserve the demonstrated before-fix failure, then prove all
original link/strong/scalar/accessibility controls, real parser-selected definitions
across six forms and three EOLs, actual implicit-key repairs, byte-distinct Unicode
keys, correct images and wrong/foreign URL negative controls. The exact hosted
fixture adds the same immutable Markdown SDK, cmark and Yams pins as the app and
copies the actual MarkdownEngine module. Locally only the pure Foundation parser
fixtures execute; native modules compile without execution.
