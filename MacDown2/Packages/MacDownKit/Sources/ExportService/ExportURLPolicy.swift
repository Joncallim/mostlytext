import Foundation

/// Rejects authored Markdown links whose URL scheme would be dangerous when
/// rendered.
///
/// `CMARK_OPT_UNSAFE` preserves raw HTML for fidelity but, in doing so,
/// disables cmark's normal dangerous-link scrub (its "safe" mode). This policy
/// restores that guard for *authored Markdown* links/images without disabling
/// raw HTML: `javascript:`, `vbscript:`, `data:` and `file:` schemes are
/// rejected at composition time, before the URL can reach the HTML output.
///
/// `data:` is rejected on authored links regardless of media type because a
/// self-contained document's own embedded resources are produced by E12's
/// manifest, never copied verbatim from authored link URLs.
public enum ExportURLPolicy {
    /// Schemes cmark's safe mode would scrub but `UNSAFE` mode does not.
    private static let rejectedSchemes: Set<String> = ["javascript", "vbscript", "data", "file"]

    /// An authored image whose bytes are inline raster data (`data:image/png;base64,…`).
    /// Raster formats cannot run script, and an image pasted inline is common; SVG and
    /// every other `data:` type stay rejected.
    private static let rasterHeaders: Set<String> = [
        "data:image/png;base64", "data:image/jpeg;base64", "data:image/jpg;base64",
        "data:image/gif;base64", "data:image/webp;base64",
    ]

    static func hasClosedRasterReferences(_ bytes: Data, mimeType: String) -> Bool {
        switch mimeType.lowercased() {
        case "image/png": bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "image/jpeg", "image/jpg": bytes.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/gif": bytes.starts(with: Data("GIF87a".utf8)) || bytes.starts(with: Data("GIF89a".utf8))
        case "image/webp": bytes.count >= 12 && bytes.prefix(4) == Data("RIFF".utf8)
            && bytes.dropFirst(8).prefix(4) == Data("WEBP".utf8)
        default: false
        }
    }

    /// Called only after the existing full URL admission. Decode a constant
    /// prefix, not the author's complete potentially large inline image.
    static func embeddedRasterReferencesAreClosed(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let comma = trimmed.firstIndex(of: ",") else { return false }
        let header = trimmed[..<comma].lowercased()
        guard rasterHeaders.contains(header) else { return false }
        let mime = String(header.dropFirst("data:".count).dropLast(";base64".count))
        let prefix = String(trimmed[trimmed.index(after: comma)...].prefix(16))
        guard let bytes = Data(base64Encoded: prefix) else { return false }
        return hasClosedRasterReferences(bytes, mimeType: mime)
    }

    public static func isEmbeddedRasterImage(_ url: String) -> Bool {
        guard url.utf8.count > 22, url.lowercased().hasPrefix("data:image/") else { return false }
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let comma = trimmed.firstIndex(of: ",") else { return false }
        let header = trimmed[..<comma].lowercased()
        guard Self.rasterHeaders.contains(String(header)) else { return false }
        return trimmed[trimmed.index(after: comma)...].utf8.allSatisfy { byte in
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39) || byte == 0x2B || byte == 0x2F || byte == 0x3D
        }
    }

    /// Returns `true` when `url` is safe to emit as an authored Markdown link
    /// or image target.
    public static func isSafe(_ url: String) -> Bool {
        guard let scheme = scheme(of: url) else {
            // Relative references have no scheme and are resolved locally.
            return true
        }
        return !rejectedSchemes.contains(scheme)
    }

    /// The lowercase scheme of `url`, or `nil` when the URL has no scheme (it is
    /// relative or a fragment).
    ///
    /// The grammar is RFC 3986's — `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`
    /// before the first `:` — read in one pass with no intermediate array. Two
    /// details match what a browser does rather than what the RFC says, because
    /// the browser is what will run the link: leading whitespace and control
    /// characters are skipped, and tab/newline/return are ignored inside the
    /// scheme. A URL that a browser would treat as `javascript:` must not be
    /// classed as scheme-less here.
    static func scheme(of url: String) -> String? {
        var name = ""
        var started = false

        for scalar in url.unicodeScalars {
            if scalar == ":" {
                return name.isEmpty ? nil : name.lowercased()
            }
            if isStripped(scalar) {
                // Leading whitespace, and tab/newline/return anywhere in the
                // scheme, are removed by URL parsers before the scheme is read.
                if !started || isIgnoredInScheme(scalar) {
                    continue
                }
                return nil
            }
            guard isSchemeCharacter(scalar, isFirst: !started) else { return nil }
            started = true
            name.unicodeScalars.append(scalar)
        }
        return nil
    }

    /// Whitespace and C0 control characters, which never appear in a URL that a
    /// parser has finished with.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x20
    }

    /// Tab, line feed and carriage return: removed from anywhere in a URL.
    private static func isIgnoredInScheme(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
    }

    private static func isSchemeCharacter(_ scalar: Unicode.Scalar, isFirst: Bool) -> Bool {
        let isLetter = (scalar.value >= 0x41 && scalar.value <= 0x5A)
            || (scalar.value >= 0x61 && scalar.value <= 0x7A)
        if isFirst {
            return isLetter
        }
        let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
        return isLetter || isDigit || scalar == "+" || scalar == "-" || scalar == "."
    }
}
