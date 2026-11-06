# Reproduce the component checks

Create the fixture with the retained Package.swift/Package.resolved, the exact
MarkdownEngine sources from the receipt's source revision, every canonical
MarkdownEngine test, and an executable target containing the byte-identical
GatedParseEngine.swift and MarkdownPublicationScenarios.swift plus Driver.swift.

Build (do not execute any SwiftPM test helper):

```sh
swift build --package-path FIXTURE -c debug --force-resolved-versions --product MarkdownSessionChecks
swift build --package-path FIXTURE -c release --force-resolved-versions --product MarkdownSessionChecks
otool -L FIXTURE/.build/arm64-apple-macosx/debug/MarkdownSessionChecks
otool -L FIXTURE/.build/arm64-apple-macosx/release/MarkdownSessionChecks
```

Require no AppKit/SwiftUI/WebKit/CoreText/CoreGraphics/QuartzCore linkage before
running either normal executable. Each run is bounded to60seconds and records
separate stdout/stderr, exit status and unchanged executable/source hashes.
The original product source returns1 with18 specific failed checks; replacing
only the actual MarkdownParseSession.swift with the candidate returns0 with
all32 checks passing. No fixture, helper, driver or dependency changes.

Compile the canonical Swift Testing suite without executing its helper:

```sh
swift build --package-path FIXTURE -c release --force-resolved-versions --target MarkdownEngineTests -Xswiftc -enable-testing
```

Full original application/package execution and native checks remain hosted.
