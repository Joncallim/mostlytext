# Quick Look automatic source compatibility

## Owner summary

Finder should show the same Markdown structure for ordinary UTF-8, UTF-8 with
a byte-order mark, and UTF-16 with a byte-order mark. Line endings and Unicode
must not change the visible result. Quick Look has no encoding chooser, so it
must refuse malformed or undeclared legacy bytes instead of guessing text.
This slice adds an end-to-end encoding check to the existing bounded Quick Look
worker. It changes no production decoding policy, file bytes or editor state.

## Baseline and decision

The implementation branch began at `main` `4bd6d38e5d1f0cb9c2d6c9db10d6d4a362c81659`
and includes the GFM source branch `645fecff3bbfb052521f28f6bd08c287e681c0a4`.
The current provider reads one selected descriptor, then calls FileCore's
`FileByteDecoder` with the automatic policy. That policy recognizes UTF-8
(with or without a BOM) and BOM-marked UTF-16 LE/BE. Other encodings require a
choice the Finder request cannot provide. The shared cmark renderer then turns
the admitted text into passive HTML. The extension never writes the source.

## Checks and remaining gate

- The package regression compares complete HTML bytes for one CJK, emoji,
  accented and right-to-left GFM document across the three BOM forms and
  LF/CRLF/CR. It also checks that malformed UTF-16 and undeclared legacy bytes
  refuse, and keeps the existing exact/over-limit and changed-file controls.
- A hosted macOS 26 Finder run must select a real UTF-16 BE, CRLF Markdown file
  in the installed app's Quick Look extension. Its accessibility tree must
  contain the decoded heading and Unicode paragraph with the MostlyText
  provider marker. The containing app remains unopened.

The selected local package run passed all ten Quick Look source tests at this
branch's initial source. Pinned SwiftFormat 0.63.1, strict SwiftLint on the
changed Swift files and diff whitespace checks pass. Hosted Finder, full CI
and final signed clean-install evidence remain separate results; this note
does not claim them from the package test.
