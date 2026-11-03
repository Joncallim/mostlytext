import AppKit
import SwiftUI

/// The first-run welcome screen (E15 deliverable 6). Shown exactly once, the
/// first time the app ever launches; see `AppDelegate.applicationDidFinishLaunching`.
struct FirstRunView: View {
    let onStartWriting: () -> Void
    let onOpenSample: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome to MostlyText")
                    .font(.largeTitle.bold())
                Text("A fast, native Markdown editor for Mac, with live preview, math, and diagrams built right in.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: 12) {
                Button("Open a Sample Document", action: onOpenSample)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("firstRunOpenSampleButton")
                Button("Start Writing", action: onStartWriting)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("firstRunStartWritingButton")
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 380)
        // Without `.contain`, SwiftUI propagates this identifier onto every
        // descendant instead of creating a container, overwriting the two
        // buttons' own identifiers (confirmed via a real accessibility-tree
        // dump: both buttons reported `firstRunWelcomeView`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstRunWelcomeView")
    }
}

/// The sample document opened by the welcome screen's "Open a Sample
/// Document" action — a brief tour of the editor's own headline features,
/// written in the Markdown it demonstrates.
enum FirstRunSampleDocument {
    static let text = """
    # Welcome to MostlyText

    This is a sample document, open for you to explore — edit it, or start a
    new one from the **File** menu whenever you're ready.

    ## Formatting

    MostlyText supports **bold**, *italic*, `inline code`, and [links](https://example.com).

    - A bullet list
    - With a couple of items
    - Including one nested below
        - Like this

    > A blockquote, for quoting something worth quoting.

    ## Code

    ```swift
    let greeting = "Hello, Markdown!"
    print(greeting)
    ```

    ## Math

    Inline math like $E = mc^2$, or a display equation:

    $$
    \\int_0^\\infty e^{-x} \\, dx = 1
    $$

    ## Diagrams

    ```mermaid
    graph LR
        Write[Write Markdown] --> Preview[Live Preview]
        Preview --> Export[Export to HTML or PDF]
    ```

    Happy writing!
    """
}
