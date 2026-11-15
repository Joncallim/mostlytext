# Retire obsolete editor highlighters before their styles reach TextKit

## Owner summary

Changing a document's language can replace the syntax highlighter while an
earlier parsing request is still running. The old request could then clear the
new highlighter's rendering attributes. The editor now retires the old style
writer before dropping it, while keeping the existing content-version guard.
This is a narrow lifetime change; it does not change parsing, theme selection,
or the document's text.

## Exact source and mechanism

- Previous Neon: `f702323168da9c6f0fb8120b844e81fd025f2124`.
- New Neon: [`e0d2f7fb506e07d55133a319b04ee3e79ee013a8`](https://github.com/Joncallim/Neon/commit/e0d2f7fb506e07d55133a319b04ee3e79ee013a8).
- The [vendored exact diff](evidence/retired-highlighter-style-boundary-2026-11-15/neon-f7023231-to-e0d2f7fb.patch)
  has SHA-256 `292065a206d6f888ee02ce0ed623b99772bb31436b74175b91ba5e39dee8b5b7`.
- The fork's `LICENSE` is unchanged, SHA-256
  `d11b5eea8e9ae2f6dd06545633e8daf0dfcbc7dbb911a20d1504c905e5808775`.
  `Package.swift`, parser source, grammar submodule, and other dependencies are
  unchanged. The diff modifies three Neon runtime files and one test file.

Neon's `TextViewSystemInterface.applyStyles` clears the application range
before it asks MostlyText's attribute provider for token colours. The provider
already rejects tokens from an obsolete generation, but it cannot undo that
earlier range clear. An older validator may also still be processing the same
document version after a language or theme change. Neon's new
`TextViewHighlighter.deactivate()` propagates to its styler and validator. The
validator checks its active state before and after both synchronous and
asynchronous token requests, before any style application. The styler also
ignores later callbacks. MostlyText calls `deactivate()` before dropping its
highlighter and incrementing its generation.

## Evidence and limits

- The hosted mounted lifecycle test on the old pin failed after the injected
  JavaScript lookup was held, the language was set to plain, the dark theme was
  selected, the whole document was replaced, and Markdown was restored. The
  direct run found 10 rendered runs against 7,213 in a fresh control, with
  12,288 obsolete attribute-provider calls. A probe run found 4 against 7,213.
  Both retained the source bytes and observed the held request. These are
  failing-before observations, not a claim that every missing run has the same
  cause.
- The new Neon regression holds an asynchronous token result, retires its
  owner without editing the content, then requires a stale result and zero
  style applications. A second test rejects new synchronous and asynchronous
  requests after retirement. The complete Neon Debug and Release suites each
  pass 46 tests across 12 suites on the new commit.
- An exact-head hosted mounted pass and app/package qualification remain
  required. This finding does not reproduce or resolve the historical
  malformed-range assertion in MostlyText issue #19.
