import Foundation

/// Security hardening for the read-only HTML preview.
///
/// The workspace-shell preview shows arbitrary `.html` files in a `WKWebView`.
/// JavaScript is already disabled at the web-view level, but that does not stop
/// a document from reaching the network via `<img src="https://…">`, remote
/// stylesheets, fonts, or CSS `url()` — any of which can leak information about
/// the viewer. `PreviewSecurity` injects a restrictive Content-Security-Policy
/// so a previewed file cannot make network requests, while still allowing the
/// document's own inline styling, embedded `data:` resources, and same-origin
/// resources served by the preview's own scheme handler
/// (`macdown-preview:` — validated by `HTMLPreviewResourceScope` before any
/// bytes are served) to render.
public enum PreviewSecurity {
    /// A restrictive Content-Security-Policy for the preview.
    ///
    /// `default-src 'none'` blocks every remote fetch and every script;
    /// inline styles, `data:` images/media/fonts, and resources served by the
    /// preview's own `macdown-preview:` scheme handler remain allowed so a
    /// document's own styling and its local images still render. Nothing can
    /// reach the network; forms and `<base>` hijacking are blocked outright.
    public static let contentSecurityPolicy =
        "default-src 'none'; script-src 'none'; style-src 'unsafe-inline' macdown-preview:; "
            + "img-src macdown-preview: data:; media-src macdown-preview: data:; "
            + "font-src macdown-preview: data:; connect-src 'none'; frame-src macdown-preview:; "
            + "object-src 'none'; form-action 'none'; base-uri 'none';"

    private static var cspMetaTag: String {
        "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
    }

    /// Returns the given HTML with a restrictive CSP `<meta>` tag injected so the
    /// preview web view cannot load remote resources.
    ///
    /// The caller's markup is preserved; only the CSP tag (and, for bare
    /// fragments, a wrapping document) is added. The CSP is placed as early as
    /// possible so it governs the whole document.
    public static func hardenedHTMLDocument(from html: String) -> String {
        // Prefer injecting into an existing <head> so full documents keep their
        // structure and their own <title>/<style> intact.
        if let headOpen = openingTagRange(of: "head", in: html) {
            var result = html
            result.insert(contentsOf: cspMetaTag, at: headOpen.upperBound)
            return result
        }
        // A document with <html> but no <head>: add a <head> holding the CSP.
        if let htmlOpen = openingTagRange(of: "html", in: html) {
            var result = html
            result.insert(contentsOf: "<head>\(cspMetaTag)</head>", at: htmlOpen.upperBound)
            return result
        }
        // A bare fragment: wrap it in a minimal hardened document.
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\(cspMetaTag)</head><body>\(html)</body></html>"
    }

    /// Finds the range of the first *real* opening `<name …>` tag, including
    /// the closing `>`.
    ///
    /// The scan is tokenizer-based rather than a raw string search so that a
    /// `<head>` that merely *appears* inside markup is never mistaken for the
    /// document's head: occurrences inside `<!-- comments -->`, inside
    /// rawtext elements (`<script>`, `<style>`, `<textarea>`, `<title>`, …),
    /// and inside quoted attribute values are all skipped. Without this, a
    /// hostile document could hide its `<head>` in a comment or a script
    /// string, seduce the CSP injection into that dead context, and render
    /// without a Content-Security-Policy.
    ///
    /// Only the exact tag name is matched — `<head>` is matched but
    /// `<header>` is not — by requiring the character after the name to end
    /// the name (`>`, `/`, or whitespace).
    private static func openingTagRange(of name: String, in html: String) -> Range<String.Index>? {
        let characters = Array(html)
        let lowerName = name.lowercased()
        var state: ScanState = .data
        var index = 0

        // Each HTML scan state advances through its own helper; the loop only
        // dispatches between them.
        while index < characters.count {
            switch state {
            case .data:
                if let range = scanDataState(
                    name: lowerName,
                    html: html,
                    characters: characters,
                    state: &state,
                    index: &index
                ) {
                    return range
                }
            case let .tag(quoted):
                scanTagState(quoted: quoted, characters: characters, state: &state, index: &index)
            case .comment:
                scanCommentState(characters: characters, state: &state, index: &index)
            case let .rawtext(name):
                scanRawtextState(name: name, characters: characters, state: &state, index: &index)
            }
        }
        return nil
    }

    /// One step in the data state: a `<` may open a comment, rawtext, the
    /// searched-for tag (returned), or an ordinary tag. Returns a tag range
    /// only when the searched-for tag is found here.
    private static func scanDataState(
        name: String,
        html: String,
        characters: [Character],
        state: inout ScanState,
        index: inout Int
    ) -> Range<String.Index>? {
        guard characters[index] == "<" else {
            index += 1
            return nil
        }
        if hasPrefix(["<", "!", "-", "-"], at: index, in: characters) {
            state = .comment
            index += 4
            return nil
        }
        if let name = rawtextTagName(at: index, in: characters) {
            state = .rawtext(name: name)
            index += 2
            return nil
        }
        if matchesTagName(name, at: index, in: characters),
           let range = tagRangeStarting(at: index, in: html, characters: characters) {
            return range
        }
        // Either an ordinary tag, or the searched-for tag with no closing `>` anywhere (`<html lang="en"` at EOF,
        // an unterminated quote): scan on as a tag so the loop always advances. Returning nil here without moving
        // spun forever on the main actor, on every open and every relaunch of the saved tab.
        state = .tag(quoted: nil)
        index += 1
        return nil
    }

    /// One step in the tag state: quoted attribute values hide `>`; an
    /// unquoted `>` ends the tag.
    private static func scanTagState(
        quoted: Character?,
        characters: [Character],
        state: inout ScanState,
        index: inout Int
    ) {
        if let quoted {
            if characters[index] == quoted {
                state = .tag(quoted: nil)
            }
        } else if characters[index] == "\"" || characters[index] == "'" {
            state = .tag(quoted: characters[index])
        } else if characters[index] == ">" {
            state = .data
        }
        index += 1
    }

    /// One step in the comment state: `-->` returns to data; everything else
    /// inside the comment is inert.
    private static func scanCommentState(
        characters: [Character],
        state: inout ScanState,
        index: inout Int
    ) {
        if hasPrefix(["-", "-", ">"], at: index, in: characters) {
            state = .data
            index += 3
        } else {
            index += 1
        }
    }

    /// One step in the rawtext state: only the matching `</name` ends it.
    private static func scanRawtextState(
        name: String,
        characters: [Character],
        state: inout ScanState,
        index: inout Int
    ) {
        // Rawtext ends only at its own matching `</name>`. A different
        // closing tag is inert text, including a fake `<head>` after it.
        // HTML `plaintext` consumes the rest of the document even if authored
        // text contains `</plaintext>`.
        if characters[index] == "<",
           name != "plaintext", rawtextCloseTagName(name, at: index, in: characters) {
            state = .tag(quoted: nil)
            index += name.count + 2
        } else {
            index += 1
        }
    }

    /// Tag names whose content is raw text: no markup inside them is parsed
    /// until the matching close tag (`</script>`, `</style>`, …).
    private static let rawtextTagNames = [
        "script", "style", "textarea", "title", "xmp",
        "plaintext", "noembed", "noframes", "noscript",
    ]

    private static func rawtextTagName(at start: Int, in characters: [Character]) -> String? {
        rawtextTagNames.first { matchesTagName($0, at: start, in: characters) }
    }

    private static func rawtextCloseTagName(_ name: String, at start: Int, in characters: [Character]) -> Bool {
        guard start + 1 < characters.count, characters[start + 1] == "/" else { return false }
        return matchesTagName(name, at: start + 1, in: characters)
    }

    /// Whether `characters[start...]` begins with a `<` followed by `name`
    /// (case-insensitive) and a tag-name boundary.
    private static func matchesTagName(_ name: String, at start: Int, in characters: [Character]) -> Bool {
        let nameCharacters = Array(name.lowercased())
        guard start + 1 + nameCharacters.count < characters.count else { return false }
        for (offset, expected) in nameCharacters.enumerated() {
            let candidate = characters[start + 1 + offset]
            if String(candidate).lowercased() != String(expected) {
                return false
            }
        }
        return isTagNameBoundary(characters[start + 1 + nameCharacters.count])
    }

    /// Returns the range of the tag beginning at `start` (`<`), scanning to
    /// the matching `>` while respecting quoted attribute values so a `>`
    /// inside an attribute does not end the tag early.
    private static func tagRangeStarting(
        at start: Int,
        in html: String,
        characters: [Character]
    ) -> Range<String.Index>? {
        var index = start + 1
        var quoted: Character?
        while index < characters.count {
            if let quote = quoted {
                if characters[index] == quote {
                    quoted = nil
                }
            } else if characters[index] == "\"" || characters[index] == "'" {
                quoted = characters[index]
            } else if characters[index] == ">" {
                return html.index(html.startIndex, offsetBy: start) ..< html.index(html.startIndex, offsetBy: index + 1)
            }
            index += 1
        }
        return nil
    }

    private static func hasPrefix(_ prefix: [Character], at start: Int, in characters: [Character]) -> Bool {
        guard start + prefix.count <= characters.count else { return false }
        for (offset, expected) in prefix.enumerated() where characters[start + offset] != expected {
            return false
        }
        return true
    }

    private static func isTagNameBoundary(_ character: Character) -> Bool {
        // HTML tokenization recognizes ASCII whitespace here. Swift's broader
        // `isWhitespace` would accept NBSP and end rawtext before the browser.
        character == ">" || character == "/" || character == " " || character == "\t"
            || character == "\n" || character == "\r" || character == "\u{000C}"
    }

    private enum ScanState: Equatable {
        case data
        case tag(quoted: Character?)
        case comment
        case rawtext(name: String)
    }
}
