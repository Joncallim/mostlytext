# Public command entry and installed-app connection

## Owner summary

Replace the command placeholder with predictable `open`, default file arguments,
stdin, `--wait`, help/version and registry-backed `formats`. Connect through the
existing bounded, instance-verified client. Cold launch targets only the enclosing
signed app, never a PATH search, shell command or guessed application identifier.
No installer, shell-profile edit or privileged helper is added.

Baseline: master `15c0fae22f7618e94c82681227057c66011be2a9`, integration
`7e9ace58a38d96a922c1d482eb78b3b0f371925b`, stacked with #557/#558. The
transport/client exchange exists, while the app listener and document admission
are still separate work. This command fails unavailable until its app supplies
that endpoint; passing command tests does not claim native open/stdin/wait.

## Arguments and dependency

Pin Apple swift-argument-parser 1.8.2 at its verified release revision, wrapping
it in CommandLineSupport. Preserve all existing locked dependencies, copy its
exact licence/notice and update inventory/notices/SBOM. The official package
has no external dependencies. The owner-confirmed public command and build product are `mostlytext`. The
internal target/module is MostlyTextCommand and the build scheme is MostlyTextCLI.
The embedded filename is mostlytext-cli, keeping it distinct from the app
executable on case-insensitive filesystems. Final app/storage identity remains
a separate manifest input.

The default and `open` commands accept structured file arguments and `--wait`.
`--` escapes option-like or reserved-command filenames. `-` is one explicit
stdin stream and cannot occur twice. A nonterminal stdin is read implicitly only
when there are no file arguments; an interactive bare command never reads stdin.
Empty stdin remains a real stream. `formats`, help and version do not read stdin,
connect or launch. Relative paths use the captured caller directory without
lexically simplifying `..` across symlinks. Apply existing path/frame limits.

Read stdin with bounded nonblocking POSIX chunks, 32 MiB maximum, finite monotonic
deadline and 50 ms cancellation polling. Restore descriptor flags; do not close
caller-owned descriptors. Decode strictly, keep exact BOM/line endings and bind
the exact bytes into the existing request descriptor. Parsing/hashing/socket
work runs off MainActor. SIGINT/SIGTERM cancel only this client/connection.

## Installed app and transport

Resolve the actual executing image physically, including an explicitly created
user-bin symlink, and require `App.app/Contents/MacOS/mostlytext-cli`. Validate its Info
plist, main executable and non-placeholder bundle identity. Embed the CLI as an
app build dependency/copy with exact bytes and its localisation resource bundle, so CLI and app update together. Warm
connection uses the OS-selected per-user endpoint, not TMPDIR or a client path.

Only definite endpoint absence/refusal before sending any request permits cold
launch/startup retries. Verify the enclosing app's static code against Apple's
code-signing anchor, the CLI's signing team and exact enclosing bundle identifier
before launching that path with NSWorkspace. Unsigned development code fails
closed for cold launch. Metadata, protocol, instance and permission failures do
not authorize launch/retry. Once connected, send exactly one request through
CommandClientExchange; connection loss never causes replay or relaunch.

Use finite startup/input/acceptance deadlines; after valid wait acceptance there
is no short editing deadline. Stable exits: success 0, usage 2, input 3, partial
open/rejection 4, unavailable 5, interrupted 130. Human diagnostics are separate
from stable wire reason codes. New CLI metadata/diagnostics enter the localisation
catalog; upstream ArgumentParser English headings/errors remain an explicit
final #17 localisation verification task, not a claim of translated CLI support.

## Verification and remaining integration

Test default/explicit open, flags/escape/reserved names, unknown options, help/
version/formats without stdin/launch, path preservation, explicit/implicit/empty
stdin, malformed/oversized/stalled input, descriptor restoration/cancellation,
physical embedded/symlink lookup and malformed/cross-container metadata. Verify
runtime policy with injected launch/connection owners in synthetic tests; never
weaken production signature checks with a public test switch. Execute only
non-launching command routes locally. Full hosted package/app tests and locked
Debug/Release builds precede merge. Actual cold/warm app/document/wait acceptance,
bootstrap UI and signing remain open; no app or real user state is launched here.

## Hosted build correction

The first full run passed all 3,139 package tests (431 suites, two existing
Neon known issues) but app+CLI dependency builds exposed a case-insensitive
intermediate-directory collision: app target MacDown2 and tool target macdown2
wrote overlapping Swift file lists, so the tool attempted to compile the app's
GeneratedAssetSymbols.swift before it existed. Rename only the internal tool
target and Swift module to MostlyTextCommand and set PRODUCT_NAME to mostlytext. The public scheme,
executable, embedding path and app identity stay the same. Retain the failed
run and require a full corrected locked run.

Additional nonlaunching checks relocate both Debug and Release executables into
a synthetic app with the resource bundle and exercise direct/user-bin-symlink
help, version and formats: all 12 pass. All 15 first-party catalogue keys exist.
These checks do not launch AppDelegate or prove compiled-catalog translations.

The next full run passed package tests and all builds, but app-target execution
found a second case-insensitive collision: copying macdown2 alongside main
executable MacDown2 overwrote the app. Embed the tool as mostlytext-cli;
public syntax, build product and optional user-bin symlink name are mostlytext. The locator follows that symlink to the distinct embedded filename.
The embed script refuses a destination aliasing the main executable and refuses
an already overwritten app executable (clean/rebuild required). Retain the
failed app bootstrap and require the complete corrected hosted run.

## Public CLI identity confirmation

On 2 November the owner confirmed mostlytext as the public CLI. The executable
build product, help/usage, unbundled version marker, scheme/build instructions
and optional user-bin command all use mostlytext. Contents/MacOS/mostlytext-cli
is the embedded implementation path, avoiding a future collision with an app
executable named MostlyText. No compatibility alias is installed automatically.
