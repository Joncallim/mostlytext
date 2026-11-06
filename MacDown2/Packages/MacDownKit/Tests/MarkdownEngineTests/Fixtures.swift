import Foundation

/// Deterministic fixtures and helpers for MarkdownEngine tests.
enum Fixtures {
    // MARK: - Front matter

    static let validFrontMatter = """
    ---
    title: Hello
    tags:
      - swift
      - markdown
    count: 42
    enabled: true
    ---
    # Body
    """

    static let malformedFrontMatter = """
    ---
    title: : : invalid
    ---
    # Body
    """

    static let nonMappingFrontMatter = """
    ---
    - one
    - two
    ---
    # Body
    """

    static let dotCloserFrontMatter = """
    ---
    title: Hello
    ...
    # Body
    """

    static let emptyFrontMatter = """
    ---
    ---
    # Body
    """

    static let bomPrefixedFrontMatter = "\u{FEFF}" + """
    ---
    title: Hello
    ---
    # Body
    """

    static let noCloserFrontMatter = """
    ---
    title: Hello

    # Body
    """

    // MARK: - Block corpus

    static let headingCorpus = """
    # Heading 1
    ## Heading 2
    ### Heading 3
    """

    static let codeBlockCorpus = """
    ```Swift
    let x = 1
    ```

        indented
        code

    ```
    no language
    ```
    """

    static let listCorpus = """
    1. First
    2. Second
       - Nested
       - Deep
    3. Third

    - Alpha
    - Bravo
    """

    static let taskListCorpus = """
    - [x] Done
    - [ ] Not done
    """

    static let blockQuoteCorpus = """
    > Line one
    > Line two
    >
    > ## Quote heading
    """

    static let tableCorpus = """
    | A | B | C |
    |---|---|---|
    | 1 | 2 | 3 |
    | 4 | 5 | 6 |
    """

    static let thematicBreakCorpus = """
    ---

    ***

    ___
    """

    static let htmlBlockCorpus = """
    <div>
    <p>Hello</p>
    </div>
    """

    // MARK: - Generators

    /// Generates a deterministic Markdown string of approximately
    /// `targetByteCount` UTF-8 bytes.
    static func markdown(targetByteCount: Int) -> String {
        let paragraph = "The quick brown fox jumps over the lazy dog.\n\n"

        var result = ""
        result.reserveCapacity(targetByteCount)

        var index = 0
        repeat {
            switch index % 6 {
            case 0:
                result += "# Heading \(index)\n\n"
                result += paragraph
            case 1:
                result += "- List item \(index)-a\n"
                result += "- List item \(index)-b\n\n"
            case 2:
                result += "> A blockquote that spans a few words.\n\n"
            case 3:
                result += "```swift\nlet x = \(index)\nlet y = x + 1\n```\n\n"
            case 4:
                result += "| A | B |\n|---|---|\n| 1 | 2 |\n\n"
            default:
                result += paragraph
            }

            index += 1
        } while result.utf8.count < targetByteCount

        return result
    }

    /// Generates a deeply nested blockquote of `depth` levels.
    static func nestedBlockquotes(depth: Int) -> String {
        let prefix = String(repeating: "> ", count: depth)
        return prefix + "Deep\n"
    }

    /// Generates a long run of emphasis delimiters that can stress parsers.
    static func emphasisBomb(length: Int) -> String {
        String(repeating: "*", count: length)
    }

    // MARK: - Polling helper

    /// Polls `predicate` until it returns `true` or `timeout` elapses.
    /// The 30 s default absorbs cooperative-pool starvation on CI: the parallel
    /// run pins every global-executor thread inside multi-second synchronous
    /// parses (10 MB cmark ≈ 21 s on the runner), and actor hops — including the
    /// ParseSpy's — queue behind them. Locally the pool is wide enough that
    /// predicates settle in milliseconds; the timeout is a bound, not a delay.
    static func wait(
        timeout: Duration = .seconds(30),
        sleep: Duration = .milliseconds(10),
        predicate: @Sendable () async -> Bool
    ) async {
        let start = ContinuousClock().now
        while await !predicate() {
            if ContinuousClock().now - start > timeout {
                return
            }
            try? await Task.sleep(for: sleep)
        }
    }
}
