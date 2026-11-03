# Export parse reuse: Release component evidence

Ordinary export previously parsed the exact Markdown source twice: once for
contributions and again for composition. It now reuses the accepted immutable
document once and releases the cache's full-tree reference before cmark work.
The separate cmark serialization and rendering/resource paths are unchanged.

The real pinned MarkdownEngine, swift-markdown, Yams and cmark run in a private
non-application harness. FrozenExportParse is copied unchanged; test assertions
are unchanged with only the app-module import adapted. Other manifest-listed
Foundation/POSIX sources are unchanged; only the unused validated-SVG receipt
DTO and theme-only fixture helper are outside that harness. No app, user store,
GUI, Daybreak, signing or account operation is performed.

`Benchmark.swift` measures two actual parses versus one parse plus validated
one-shot reuse. Each approximately 1-MiB corpus has three paired Release
samples, alternating order. Timed intervals end before result-equality checks;
all checksums and complete parsed values agree. Raw samples, exact toolchain/OS
and architecture are in `timings.json`; runtime pins and source hashes accompany
it. These are parser-component timings, not whole-export, editor, memory/RSS or
PDF responsiveness evidence.

| Input | Bytes | Two parses median | One parse + reuse median | Work removed |
|---|---:|---:|---:|---:|
| Ordinary prose/inline markup | 1,048,648 | 446.11 ms | 220.71 ms | 225.40 ms |
| Technical headings/quotes/code/raw HTML | 1,048,593 | 598.55 ms | 300.19 ms | 298.36 ms |

The private harness passes 134 tests in 13 suites in Debug and Release, including
real parser/cache source/options/revision/cancellation guards, one-shot versus
repeatable ownership, syscall-interleaving and publication controls. Hosted app
tests must separately prove that ordinary HTML/PDF orchestration uses that
single upstream parse and retains all snapshot assertions. Local app/test
targets compile only. Full exact-head hosted checks remain required before
integration; final native and independent release evidence remains open.

Initial harness setup fetched only existing pins but warned about duplicate
local/remote cmark identities. The corrected private graph uses the exact
official 0.8.0 URL/revision and verified local Markdown/Yams checkouts, with a
resolved-file check before execution. Initial setup and compilation logs remain
in the external evidence directory; no repository dependency or pin changed.
